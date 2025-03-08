// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MyNft.sol";
import "../src/MyToken.sol";
import "../src/NftMarket1.sol";

// 测试与openzeppelin的Upgrades Plugins改造后的合约 部署合约
contract NftMarket1Test is Test {
    MyNft public nft;
    MyToken public token;
    NftMarket1 public market;
    
    address public deployer;
    address public seller;
    address public buyer;
    
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    string public constant TOKEN_URI = "ipfs://QmExample";
    
    function setUp() public {
        // 创建测试账户
        deployer = makeAddr("deployer");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        
        // 部署合约
        vm.startPrank(deployer);
        {
            // 部署 NFT、代币和市场合约
            nft = new MyNft();
            token = new MyToken();
            market = new NftMarket1();
            
            // 初始化市场合约
            market.initialize(address(token));
            
            // 铸造代币给买家
            token.mint(buyer, INITIAL_BALANCE);
            
            // 铸造 NFT 给卖家
            nft.mint(seller, TOKEN_URI);
        }
        vm.stopPrank();
    }

    // 测试上架 NFT
    function testList() public {
        vm.startPrank(seller);
        {
            // 授权市场合约操作 NFT
            nft.approve(address(market), 1);
            // 上架 NFT
            market.list(address(nft), 1, 100 ether);
        }
        vm.stopPrank();
        
        // 验证上架信息
        (
            address nftContract,
            uint256 tokenId,
            uint256 price,
            address nftSeller,
            uint256 deadline
        ) = market.listings(address(nft), 1);
        
        assertEq(nftContract, address(nft));
        assertEq(tokenId, 1);
        assertEq(price, 100 ether);
        assertEq(nftSeller, seller);
        assertEq(deadline, 0);  // V1 中 deadline 应该为 0
    }

    // 测试取消上架
    function testCancelListing() public {
        // 先上架
        vm.startPrank(seller);
        {
            nft.approve(address(market), 1);
            market.list(address(nft), 1, 100 ether);
            // 取消上架
            market.cancelListing(address(nft), 1);
        }
        vm.stopPrank();
        
        // 验证上架信息已被清除
        (,,, address nftSeller,) = market.listings(address(nft), 1);
        assertEq(nftSeller, address(0));
    }

    // 测试购买 NFT
    function testBuyNFT() public {
        uint256 price = 100 ether;
        
        // 卖家上架 NFT
        vm.startPrank(seller);
        {
            nft.approve(address(market), 1);
            market.list(address(nft), 1, price);
        }
        vm.stopPrank();
        
        // 买家授权并购买 NFT
        vm.startPrank(buyer);
        {
            token.approve(address(market), price);
            market.buyNFT(address(nft), 1);
        }
        vm.stopPrank();
        
        // 验证交易结果
        assertEq(nft.ownerOf(1), buyer);
        assertEq(token.balanceOf(seller), price);
        assertEq(token.balanceOf(buyer), INITIAL_BALANCE - price);
        
        // 验证上架信息已被清除
        (,,, address nftSeller,) = market.listings(address(nft), 1);
        assertEq(nftSeller, address(0));
    }

    // 测试错误情况
    function testCannotBuyUnlistedNFT() public {
        vm.startPrank(buyer);
        vm.expectRevert("NFT not listed");
        market.buyNFT(address(nft), 1);
        vm.stopPrank();
    }

    function testCannotBuyOwnNFT() public {
        vm.startPrank(seller);
        {
            nft.approve(address(market), 1);
            market.list(address(nft), 1, 100 ether);
            vm.expectRevert("Cannot buy own NFT");
            market.buyNFT(address(nft), 1);
        }
        vm.stopPrank();
    }

    function testCannotListWithoutApproval() public {
        vm.startPrank(seller);
        vm.expectRevert("NFT not approved for marketplace");
        market.list(address(nft), 1, 100 ether);
        vm.stopPrank();
    }

    function testCannotListWithZeroPrice() public {
        vm.startPrank(seller);
        {
            nft.approve(address(market), 1);
            vm.expectRevert("Price must be greater than 0");
            market.list(address(nft), 1, 0);
        }
        vm.stopPrank();
    }

    function testCannotCancelUnlistedNFT() public {
        vm.startPrank(seller);
        vm.expectRevert("Not listed");
        market.cancelListing(address(nft), 1);
        vm.stopPrank();
    }

    function testCannotCancelOthersListing() public {
        // 卖家上架
        vm.startPrank(seller);
        {
            nft.approve(address(market), 1);
            market.list(address(nft), 1, 100 ether);
        }
        vm.stopPrank();

        // 买家尝试取消上架
        vm.startPrank(buyer);
        vm.expectRevert("Not the seller");
        market.cancelListing(address(nft), 1);
        vm.stopPrank();
    }
}