// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 导入 Foundry 的测试框架
import "forge-std/Test.sol";
// 导入需要测试的合约
import "../src/MyNft.sol";
import "../src/MyToken.sol";
import "../src/NftMarket2.sol";

// 测试与openzeppelin的Upgrades Plugins改造后的合约 升级合约
// 测试合约需要继承 Test，这样可以使用 Foundry 提供的测试工具
contract NftMarket2Test is Test {
    // 声明要测试的合约实例
    MyNft public nft;
    MyToken public token;
    NftMarket2 public market;
    
    // 定义测试中需要用到的地址
    address public deployer;  // 合约部署者
    address public seller;    // NFT卖家
    address public buyer;     // NFT买家
    uint256 public sellerPrivateKey;  // 卖家的私钥（用于签名）
    
    // 常量定义
    uint256 public constant INITIAL_BALANCE = 1000 ether;  // 初始代币数量
    string public constant TOKEN_URI = "ipfs://QmExample";  // NFT的URI
    
    // setUp 函数在每个测试用例执行前都会运行
    // 用于设置测试环境和初始状态
    function setUp() public {
        // 创建测试账户
        sellerPrivateKey = 0xA11CE;  // 固定私钥便于测试
        seller = vm.addr(sellerPrivateKey);
        deployer = makeAddr("deployer");
        buyer = makeAddr("buyer");
        
        vm.startPrank(deployer);
        {
            // 部署合约
            nft = new MyNft();
            token = new MyToken();
            market = new NftMarket2();
            
            // 初始化市场合约
            market.initialize(address(token));
            
            // 铸造代币给买家
            token.mint(buyer, INITIAL_BALANCE);
            
            // 铸造 NFT 给卖家
            nft.mint(seller, TOKEN_URI);
        }
        vm.stopPrank();
    }

    // 测试通过签名上架 NFT
    function testListWithSignature() public {
        uint256 price = 100 ether;
        uint256 deadline = block.timestamp + 1 days;
        
        // 生成签名
        bytes memory signature = getSignature(
            address(nft),
            1,
            price,
            deadline
        );
        
        // 授权市场合约
        vm.prank(seller);
        nft.approve(address(market), 1);
        
        // 使用签名上架
        market.listWithSignature(
            address(nft),
            1,
            price,
            deadline,
            signature
        );
        
        // 验证上架信息
        (
            address nftContract,
            uint256 tokenId,
            uint256 listingPrice,
            address nftSeller,
            uint256 listingDeadline
        ) = market.listings(address(nft), 1);
        
        assertEq(nftContract, address(nft));
        assertEq(tokenId, 1);
        assertEq(listingPrice, price);
        assertEq(nftSeller, seller);
        assertEq(listingDeadline, deadline);
    }

    // 测试购买已签名上架的 NFT
    function testBuySignedNFT() public {
        uint256 price = 100 ether;
        uint256 deadline = block.timestamp + 1 days;
        
        // 上架 NFT
        bytes memory signature = getSignature(
            address(nft),
            1,
            price,
            deadline
        );
        
        vm.prank(seller);
        nft.approve(address(market), 1);
        
        market.listWithSignature(
            address(nft),
            1,
            price,
            deadline,
            signature
        );
        
        // 买家购买
        vm.startPrank(buyer);
        {
            token.approve(address(market), price);
            market.buyNFT(address(nft), 1);
        }
        vm.stopPrank();
        
        assertEq(nft.ownerOf(1), buyer);
        assertEq(token.balanceOf(seller), price);
        assertEq(token.balanceOf(buyer), INITIAL_BALANCE - price);
    }

    // 测试过期签名应该失败
    // testFail 前缀表示这个测试预期会失败
    function test_RevertWhen_SignatureExpired() public {
        uint256 price = 100 ether;
        uint256 deadline = block.timestamp - 1; // 已过期的时间戳
        
        bytes memory signature = getSignature(
            address(nft),
            1,
            price,
            deadline
        );
        
        vm.prank(seller);
        nft.approve(address(market), 1);
        
        vm.expectRevert("Signature expired");
        market.listWithSignature(
            address(nft),
            1,
            price,
            deadline,
            signature
        );
    }

    // 测试常规上架功能
    function testListNFT() public {
        vm.startPrank(seller);
        {
            nft.approve(address(market), 1);
            market.list(address(nft), 1, 100 ether);
        }
        vm.stopPrank();
        
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
        assertEq(deadline, 0);
    }

    // 测试取消上架功能
    function testCancelListing() public {
        vm.startPrank(seller);
        {
            nft.approve(address(market), 1);
            market.list(address(nft), 1, 100 ether);
            market.cancelListing(address(nft), 1);
        }
        vm.stopPrank();
        
        (,,,address nftSeller,) = market.listings(address(nft), 1);
        assertEq(nftSeller, address(0));  // 上架信息已被清除
    }

    // 辅助函数：生成 EIP-712 签名
    function getSignature(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 domainSeparator = market.DOMAIN_SEPARATOR();
        bytes32 typeHash = market.LISTING_TYPEHASH();
        
        bytes32 structHash = keccak256(abi.encode(
            typeHash,
            nftContract,
            tokenId,
            price,
            deadline
        ));
        
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
