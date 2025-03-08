// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./MyToken.sol";

// 已部署到Sepolia测试网的IMPLEMENTATION 升级合约
/// @custom:oz-upgrades-from NftMarket1
contract NftMarket2 is Initializable, ReentrancyGuardUpgradeable, IERC721Receiver, ITokenReceiver {
    using ECDSA for bytes32;

    // ====== Storage layout v2 ======
    // 注意：继承的合约也会占用存储槽
    // Initializable: 1 slot
    // ReentrancyGuardUpgradeable: 1 slot
    
    // 必须与 v1 的前三个槽位完全匹配
    MyToken public paymentToken;  // slot 0: 支付代币合约地址 (address: 20 bytes)
    
    // slot 1: NFT 上架信息映射
    // key1: nft合约地址 (address)
    // key2: tokenId (uint256)
    // value: Listing 结构体
    mapping(address => mapping(uint256 => Listing)) public listings;
    
    // slot 2: EIP-712 域分隔符
    bytes32 public DOMAIN_SEPARATOR;  // 32 bytes
    
    // v2 新增的存储变量
    // slot 3: 已使用的签名记录
    // key: 签名字节串
    // value: 是否已使用
    mapping(bytes => bool) public usedSignatures;

    // Listing 结构体定义 (不占用存储槽，只是定义了数据结构)
    struct Listing {
        address nftContract;    // NFT 合约地址
        uint256 tokenId;       // NFT token ID
        uint256 price;         // 价格
        address seller;        // 卖家地址
        uint256 deadline;      // 截止时间（V2中用于签名上架）
    }

    // 常量（不占用存储槽）
    bytes32 public constant LISTING_TYPEHASH = keccak256(
        "List(address nftContract,uint256 tokenId,uint256 price,uint256 deadline)"
    );

    // 预留 47 个槽位用于后续升级（比 v1 少 1 个，因为使用了 1 个新槽位）
    uint256[47] private __gap;
    // ==== End of storage layout ====

    event NFTListed(address indexed nftContract, uint256 indexed tokenId, address seller, uint256 price, uint256 deadline);
    event NFTSold(address indexed nftContract, uint256 indexed tokenId, address seller, address buyer, uint256 price);
    event ListingCanceled(address indexed nftContract, uint256 indexed tokenId, address seller);

    function initialize(address _paymentToken) public reinitializer(2) {
        // 添加父合约的初始化调用
        __ReentrancyGuard_init();
        
        paymentToken = MyToken(_paymentToken);
        
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("NFTMarket"),
                keccak256("2"),
                block.chainid,
                address(this)
            )
        );
    }

    function list(address nftContract, uint256 tokenId, uint256 price) external {
        require(price > 0, "Price must be greater than 0");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not the owner");
        require(listings[nftContract][tokenId].seller == address(0), "Already listed");
        require(
            IERC721(nftContract).getApproved(tokenId) == address(this) ||
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)),
            "NFT not approved for marketplace"
        );
        
        listings[nftContract][tokenId] = Listing(nftContract, tokenId, price, msg.sender, 0);
        emit NFTListed(nftContract, tokenId, msg.sender, price, 0);
    }

    function listWithSignature(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        bytes memory signature
    ) external {
        require(block.timestamp <= deadline, "Signature expired");
        require(!usedSignatures[signature], "Signature already used");
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(
                    LISTING_TYPEHASH,
                    nftContract,
                    tokenId,
                    price,
                    deadline
                ))
            )
        );
        
        address signer = digest.recover(signature);
        require(IERC721(nftContract).ownerOf(tokenId) == signer, "Not the owner");
        require(
            IERC721(nftContract).getApproved(tokenId) == address(this) ||
            IERC721(nftContract).isApprovedForAll(signer, address(this)),
            "NFT not approved for marketplace"
        );
        
        usedSignatures[signature] = true;
        listings[nftContract][tokenId] = Listing(nftContract, tokenId, price, signer, deadline);
        emit NFTListed(nftContract, tokenId, signer, price, deadline);
    }

    function cancelListing(address nftContract, uint256 tokenId) external {
        Listing memory listing = listings[nftContract][tokenId];
        require(listing.seller != address(0), "Not listed");
        require(listing.seller == msg.sender, "Not the seller");
        
        delete listings[nftContract][tokenId];
        emit ListingCanceled(nftContract, tokenId, msg.sender);
    }

    function buyNFT(address nftContract, uint256 tokenId) external nonReentrant {
        Listing memory listing = listings[nftContract][tokenId];
        require(listing.seller != address(0), "NFT not listed");
        require(listing.seller != msg.sender, "Cannot buy own NFT");
        if (listing.deadline > 0) {
            require(block.timestamp <= listing.deadline, "Listing expired");
        }
        
        bool success = paymentToken.transferWithCallback(
            msg.sender,
            address(this),
            listing.price,
            abi.encode(nftContract, tokenId)
        );
        require(success, "Token transfer failed");
    }

    function tokensReceived(
        address operator,
        address /*from*/,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(msg.sender == address(paymentToken), "Invalid token");
        
        (address nftContract, uint256 tokenId) = abi.decode(data, (address, uint256));
        
        Listing memory listing = listings[nftContract][tokenId];
        require(listing.seller != address(0), "NFT not listed");
        require(listing.price == amount, "Incorrect payment amount");
        require(listing.seller != operator, "Cannot buy own NFT");
        if (listing.deadline > 0) {
            require(block.timestamp <= listing.deadline, "Listing expired");
        }

        delete listings[nftContract][tokenId];
        paymentToken.transfer(listing.seller, amount);
        IERC721(nftContract).transferFrom(listing.seller, operator, tokenId);
        
        emit NFTSold(nftContract, tokenId, listing.seller, operator, amount);
        return true;
    }

    function onERC721Received(      
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
