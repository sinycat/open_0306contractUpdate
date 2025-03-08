// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/MyNft.sol";
import "../src/MyToken.sol";
import "../src/NftMarket2.sol";

// 集成测试部署后的合约,升级后的合约
contract IntegrationTest is Test {
    MyNft nft;
    MyToken token;
    NftMarket2 market;
    
    address deployer;
    address seller;
    address buyer;
    
    function setUp() public {
        // 从环境变量获取合约地址
        address nftAddress = vm.envAddress("NFT_ADDRESS");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        
        // 连接到已部署的合约
        nft = MyNft(nftAddress);
        token = MyToken(tokenAddress);
        market = NftMarket2(proxyAddress);
        
        // 设置测试账户
        deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        
        // 给测试账户一些 ETH (改得更小)
        vm.deal(seller, 0.01 ether);
        vm.deal(buyer, 0.01 ether);
        
        // 铸造 ERC20 代币给买家 (使用更合理的数量)
        vm.prank(deployer);
        token.mint(buyer, 1000);  // 1000 个代币单位，不用 ether
        
        // 铸造 NFT 给卖家
        vm.prank(deployer);
        nft.mint(seller, "ipfs://test");
    }

    // 测试基本信息
    function testDeployedContracts() public view {
        // 验证合约地址
        assertEq(address(nft), vm.envAddress("NFT_ADDRESS"));
        assertEq(address(token), vm.envAddress("TOKEN_ADDRESS"));
        assertEq(address(market), vm.envAddress("PROXY_ADDRESS"));
        
        // 验证市场合约的支付代币
        assertEq(address(market.paymentToken()), address(token));
    }

    // 测试签名上架功能
    function testListWithSignature() public {
        uint256 tokenId = 1;
        uint256 price = 100;  // 100 个代币单位
        uint256 deadline = block.timestamp + 1 days;
        
        // 生成卖家的签名
        uint256 sellerKey = uint256(keccak256(abi.encodePacked("seller")));
        bytes memory signature = getSignature(
            address(nft),
            tokenId,
            price,
            deadline,
            sellerKey
        );
        
        vm.startPrank(seller);
        {
            // 授权市场合约
            nft.approve(address(market), tokenId);
            
            // 使用签名上架
            market.listWithSignature(
                address(nft),
                tokenId,
                price,
                deadline,
                signature
            );
        }
        vm.stopPrank();
        
        // 验证上架信息
        (
            address listedNft,
            uint256 listedTokenId,
            uint256 listedPrice,
            address listedSeller,
            uint256 listedDeadline
        ) = market.listings(address(nft), tokenId);
        
        assertEq(listedNft, address(nft));
        assertEq(listedTokenId, tokenId);
        assertEq(listedPrice, price);
        assertEq(listedSeller, seller);
        assertEq(listedDeadline, deadline);
    }

    // 测试购买功能
    function testBuyNFT() public {
        uint256 tokenId = 1;
        uint256 price = 100;  // 100 个代币单位
        
        // 先上架 NFT
        vm.startPrank(seller);
        {
            nft.approve(address(market), tokenId);
            market.list(address(nft), tokenId, price);
        }
        vm.stopPrank();
        
        // 买家购买
        vm.startPrank(buyer);
        {
            token.approve(address(market), price);
            market.buyNFT(address(nft), tokenId);
        }
        vm.stopPrank();
        
        // 验证交易结果
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(token.balanceOf(seller), price);
    }

    // 辅助函数：生成签名
    function getSignature(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        uint256 privateKey
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
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
} 