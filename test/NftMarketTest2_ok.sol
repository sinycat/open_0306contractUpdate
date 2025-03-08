// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 导入 Foundry 的测试框架
import "forge-std/Test.sol";
// 导入需要测试的合约
import "../src/MyNft.sol";
import "../src/MyToken.sol";
import "../src/NftMarket2_ok.sol";

// 测试本地Anvil部署的合约 升级合约
// 测试合约需要继承 Test，这样可以使用 Foundry 提供的测试工具
contract NftMarketTest2_ok  is Test {
    // 声明要测试的合约实例
    MyNft public nft;
    MyToken public token;
    NFTMarket2_ok public market;
    
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
        // 创建确定性的私钥和地址
        sellerPrivateKey = 0xA11CE;  // 设置一个固定的私钥
        seller = vm.addr(sellerPrivateKey);  // 使用 vm.addr 从私钥派生对应的地址
        
        // makeAddr 创建确定性的地址，参数作为种子
        deployer = makeAddr("deployer");
        buyer = makeAddr("buyer");
        
        // vm.startPrank(address) 之后的所有调用都会使用指定地址作为 msg.sender
        vm.startPrank(deployer);
        {
            // 部署所有合约
            nft = new MyNft();
            token = new MyToken();
            market = new NFTMarket2_ok(address(token));
            
            // 铸造代币给买家
            token.mint(buyer, INITIAL_BALANCE);
            
            // 铸造NFT给卖家
            nft.mint(seller, TOKEN_URI);
        }
        // vm.stopPrank() 结束地址模拟
        vm.stopPrank();
    }

    // 测试通过签名上架 NFT
    function testListWithSignature() public {
        // vm.prank(address) 只将下一个调用的 msg.sender 设为指定地址
        vm.prank(seller);
        nft.approve(address(market), 1);  // 授权市场合约操作 NFT
        
        // 准备签名数据
        uint256 price = 100 ether;
        uint256 deadline = block.timestamp + 1 days;
        
        // 获取签名
        bytes memory signature = getSignature(
            address(nft),
            1,
            price,
            deadline
        );
        
        // 上架 NFT（任何人都可以提交签名上架）
        market.listWithSignature(
            address(nft),
            1,
            price,
            deadline,
            signature
        );
        
        // 使用多重返回值验证上架信息
        (
            address nftContract,
            uint256 tokenId,
            uint256 listedPrice,
            address nftSeller,
            uint256 listedDeadline
        ) = market.listings(address(nft), 1);
        
        // assertEq 用于断言相等，如果不相等则测试失败
        assertEq(nftContract, address(nft));
        assertEq(tokenId, 1);
        assertEq(listedPrice, price);
        assertEq(nftSeller, seller);
        assertEq(listedDeadline, deadline);
    }

    // 测试购买已签名上架的 NFT
    function testBuySignedNFT() public {
        // 卖家授权并上架
        vm.prank(seller);
        nft.approve(address(market), 1);
        
        uint256 price = 100 ether;
        uint256 deadline = block.timestamp + 1 days;
        bytes memory signature = getSignature(
            address(nft),
            1,
            price,
            deadline
        );
        
        market.listWithSignature(
            address(nft),
            1,
            price,
            deadline,
            signature
        );
        
        // 买家授权并购买
        vm.startPrank(buyer);
        {
            token.approve(address(market), price);
            market.buyNFT(address(nft), 1);
        }
        vm.stopPrank();
        
        // 验证交易结果
        assertEq(nft.ownerOf(1), buyer);  // NFT 所有权已转移给买家
        assertEq(token.balanceOf(seller), price);  // 卖家收到代币
        assertEq(token.balanceOf(buyer), INITIAL_BALANCE - price);  // 买家支付了代币
    }

    // 测试过期签名应该失败
    // testFail 前缀表示这个测试预期会失败
    function testFailExpiredSignature() public {
        vm.prank(seller);
        nft.approve(address(market), 1);
        
        uint256 price = 100 ether;
        uint256 deadline = block.timestamp - 1;  // 已过期的时间戳
        
        bytes memory signature = getSignature(
            address(nft),
            1,
            price,
            deadline
        );
        
        // 这个调用应该失败，因为签名已过期
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
        ) = market.listings(address(nft), 1);
        assertEq(nftContract, address(nft));
        assertEq(tokenId, 1);
        assertEq(price, 100 ether);
        assertEq(nftSeller, seller);
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
        // 获取域分隔符
        bytes32 domainSeparator = market.DOMAIN_SEPARATOR();
        // 获取类型哈希
        bytes32 typeHash = market.LISTING_TYPEHASH();
        
        // 计算结构体哈希
        bytes32 structHash = keccak256(abi.encode(
            typeHash,
            nftContract,
            tokenId,
            price,
            deadline
        ));
        
        // 计算最终待签名的消息哈希
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));
        
        // 使用 vm.sign 进行签名
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPrivateKey, digest);
        // 将签名组件打包成字节数组
        return abi.encodePacked(r, s, v);
    }
}
