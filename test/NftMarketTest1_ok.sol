// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MyNft.sol";
import "../src/MyToken.sol";
import "../src/NftMarket1_ok.sol";

// 测试本地Anvil部署的合约 部署合约
contract NftMarketTest1_ok is Test {
    MyNft public nft;
    MyToken public token;
    NFTMarket1_ok public market;
    
    address public owner = address(1);
    address public seller = address(2);
    address public buyer = address(3);
    
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    string public constant TOKEN_URI = "ipfs://QmExample";
    
    function setUp() public {
        // 部署合约
        vm.startPrank(owner);
        nft = new MyNft();
        token = new MyToken();
        market = new NFTMarket1_ok(address(token));
        vm.stopPrank();

        // 给买家和卖家铸造代币
        vm.startPrank(owner);
        token.mint(seller, INITIAL_BALANCE);
        token.mint(buyer, INITIAL_BALANCE);
        vm.stopPrank();
    }

    function testMintNFT() public {
        vm.startPrank(owner);
        uint256 tokenId = nft.mint(seller, TOKEN_URI);
        assertEq(nft.ownerOf(tokenId), seller);
        assertEq(nft.tokenURI(tokenId), TOKEN_URI);
        vm.stopPrank();
    }

    function testListNFT() public {
        // 铸造NFT给卖家
        vm.prank(owner);
        uint256 tokenId = nft.mint(seller, TOKEN_URI);
        
        // 卖家授权并上架NFT
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, 100 ether);
        vm.stopPrank();
        
        // 验证上架信息
        (address nftContract, uint256 listedTokenId, uint256 price, address nftSeller) = market.listings(address(nft), tokenId);
        assertEq(nftContract, address(nft));
        assertEq(listedTokenId, tokenId);
        assertEq(price, 100 ether);
        assertEq(nftSeller, seller);
    }

    function testBuyNFT() public {
        // 铸造并上架NFT
        vm.prank(owner);
        uint256 tokenId = nft.mint(seller, TOKEN_URI);
        
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, 100 ether);
        vm.stopPrank();
        
        // 买家授权代币给市场合约
        vm.startPrank(buyer);
        token.approve(address(market), 100 ether);
        
        // 购买NFT
        market.buyNFT(address(nft), tokenId);
        vm.stopPrank();
        
        // 验证交易结果
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(token.balanceOf(seller), INITIAL_BALANCE + 100 ether);
        assertEq(token.balanceOf(buyer), INITIAL_BALANCE - 100 ether);
    }

    function testCancelListing() public {
        // 铸造并上架NFT
        vm.prank(owner);
        uint256 tokenId = nft.mint(seller, TOKEN_URI);
        
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, 100 ether);
        
        // 取消上架
        market.cancelListing(address(nft), tokenId);
        vm.stopPrank();
        
        // 验证取消结果
        (,,,address nftSeller) = market.listings(address(nft), tokenId);
        assertEq(nftSeller, address(0));
    }

    function testFailBuyOwnNFT() public {
        // 铸造并上架NFT
        vm.prank(owner);
        uint256 tokenId = nft.mint(seller, TOKEN_URI);
        
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, 100 ether);
        
        // 尝试购买自己的NFT（应该失败）
        token.approve(address(market), 100 ether);
        market.buyNFT(address(nft), tokenId);
        vm.stopPrank();
    }

    function testFailInsufficientBalance() public {
        // 铸造并上架NFT
        vm.prank(owner);
        uint256 tokenId = nft.mint(seller, TOKEN_URI);
        
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, INITIAL_BALANCE + 1 ether);
        vm.stopPrank();
        
        // 尝试购买超出余额的NFT（应该失败）
        vm.startPrank(buyer);
        token.approve(address(market), INITIAL_BALANCE + 1 ether);
        market.buyNFT(address(nft), tokenId);
        vm.stopPrank();
    }
} 