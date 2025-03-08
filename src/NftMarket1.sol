// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MyToken.sol";

//  已部署到Sepolia测试网的IMPLEMENTATION合约
contract NftMarket1 is Initializable, ReentrancyGuardUpgradeable, IERC721Receiver, ITokenReceiver {
    // ====== Storage layout v1 ======
    // 注意：继承的合约也会占用存储槽
    // Initializable: 1 slot
    // ReentrancyGuardUpgradeable: 1 slot
    
    // 合约自身的存储变量
    MyToken public paymentToken;  // slot 0: 支付代币合约地址 (address: 20 bytes)
    
    // slot 1: NFT 上架信息映射
    // key1: nft合约地址 (address)
    // key2: tokenId (uint256)
    // value: Listing 结构体
    mapping(address => mapping(uint256 => Listing)) public listings;
    
    // slot 2: EIP-712 域分隔符
    bytes32 public DOMAIN_SEPARATOR;  // 32 bytes

    // Listing 结构体定义 (不占用存储槽，只是定义了数据结构)
    // 在 listings 映射中，每个 Listing 实例会占用连续的存储位置
    struct Listing {
        address nftContract;    // NFT 合约地址
        uint256 tokenId;       // NFT token ID
        uint256 price;         // 价格
        address seller;        // 卖家地址
        uint256 deadline;      // 截止时间（V1中默认为0）
    }

    // 预留 48 个槽位用于后续升级
    uint256[48] private __gap;
    // ==== End of storage layout ====

    event NFTListed(address indexed nftContract, uint256 indexed tokenId, address seller, uint256 price, uint256 deadline);
    event NFTSold(address indexed nftContract, uint256 indexed tokenId, address seller, address buyer, uint256 price);
    event ListingCanceled(address indexed nftContract, uint256 indexed tokenId, address seller);

    function initialize(address _paymentToken) public initializer {
        __ReentrancyGuard_init();
        paymentToken = MyToken(_paymentToken);
        
        // 添加 DOMAIN_SEPARATOR 初始化
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("NFTMarket"),
                keccak256("1"),  // 版本号为 1
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