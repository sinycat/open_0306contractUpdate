// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MyToken.sol";

// 还未适应openzeppelin的Upgrades Plugins,功能已完备
contract NFTMarket1_ok is ReentrancyGuard, IERC721Receiver, ITokenReceiver {
    MyToken public immutable paymentToken;

    struct Listing {
        address nftContract;
        uint256 tokenId;
        uint256 price;
        address seller;
    }

    // nftContract => tokenId => Listing
    mapping(address => mapping(uint256 => Listing)) public listings;

    event NFTListed(address indexed nftContract, uint256 indexed tokenId, address seller, uint256 price);
    event NFTSold(address indexed nftContract, uint256 indexed tokenId, address seller, address buyer, uint256 price);
    event ListingCanceled(address indexed nftContract, uint256 indexed tokenId, address seller);

    constructor(address _paymentToken) {
        paymentToken = MyToken(_paymentToken);
    }

    function list(address nftContract, uint256 tokenId, uint256 price) external {
        require(price > 0, "Price must be greater than 0");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not the owner");
        
        // 检查是否已经上架
        require(listings[nftContract][tokenId].seller == address(0), "Already listed");
        
        // 检查是否已经授权给市场合约
        require(
            IERC721(nftContract).getApproved(tokenId) == address(this) ||
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)),
            "NFT not approved for marketplace"
        );
        
        listings[nftContract][tokenId] = Listing(nftContract, tokenId, price, msg.sender);
        emit NFTListed(nftContract, tokenId, msg.sender, price);
    }

    function cancelListing(address nftContract, uint256 tokenId) external {
        Listing memory listing = listings[nftContract][tokenId];
        // 检查是否在上架列表中
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
            msg.sender,           // operator (买家)
            address(this),        // to (市场合约)
            listing.price,        // amount
            abi.encode(nftContract, tokenId)  // data
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

        // 先删除listing，防止重入
        delete listings[nftContract][tokenId];

        // 转移代币给卖家
        paymentToken.transfer(listing.seller, amount);
        
        // 转移NFT给买家
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