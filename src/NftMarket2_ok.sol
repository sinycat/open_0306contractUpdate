// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./MyToken.sol";

// 还未适应openzeppelin的Upgrades Plugins,但升级功能已完备
contract NFTMarket2_ok is ReentrancyGuard, IERC721Receiver, ITokenReceiver {
    using ECDSA for bytes32;

    MyToken public immutable paymentToken;
    
    // 用于验证签名的域分隔符
    bytes32 public immutable DOMAIN_SEPARATOR;
    
    // 签名的类型哈希
    bytes32 public constant LISTING_TYPEHASH = keccak256(
        "List(address nftContract,uint256 tokenId,uint256 price,uint256 deadline)"
    );

    struct Listing {
        address nftContract;
        uint256 tokenId;
        uint256 price;
        address seller;
        uint256 deadline;  // 新增：签名的截止时间
    }

    mapping(address => mapping(uint256 => Listing)) public listings;
    
    // 用于防止重放攻击
    mapping(bytes => bool) public usedSignatures;

    event NFTListed(address indexed nftContract, uint256 indexed tokenId, address seller, uint256 price, uint256 deadline);
    event NFTSold(address indexed nftContract, uint256 indexed tokenId, address seller, address buyer, uint256 price);
    event ListingCanceled(address indexed nftContract, uint256 indexed tokenId, address seller);

    constructor(address _paymentToken) {
        paymentToken = MyToken(_paymentToken);
        
        // 计算域分隔符
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("NFTMarket"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    // 常规上架功能保持不变
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

    // 新增：通过签名上架
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
