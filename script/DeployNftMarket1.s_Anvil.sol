// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../src/NftMarket1.sol";
import "../src/MyToken.sol";
import "../src/MyNft.sol";

// Anvil部署 测试通过
contract DeployNftMarket1Script_Anvil is Script {
    function run() external {
        // Anvil 的默认第一个账户私钥
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Starting deployment from address:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署 MyToken
        MyToken token = new MyToken();
        console.log("MyToken deployed at:", address(token));

        // 2. 部署 MyNft
        MyNft nft = new MyNft();
        console.log("MyNft deployed at:", address(nft));

        // 3. 部署可升级的 NftMarket1
        address proxy = Upgrades.deployTransparentProxy(
            "NftMarket1.sol",
            deployer,
            abi.encodeCall(NftMarket1.initialize, (address(token)))
        );
        
        address implementation = Upgrades.getImplementationAddress(proxy);
        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        require(proxy != address(0), "Deployment failed: proxy is zero address");
        require(implementation != address(0), "Deployment failed: implementation is zero address");
        require(proxyAdmin != address(0), "Deployment failed: proxyAdmin is zero address");

        console.log("\n==== Deployment Successful! ====");
        console.log("TOKEN_ADDRESS=", address(token));
        console.log("NFT_ADDRESS=", address(nft));
        console.log("PROXY_ADDRESS=", proxy);
        console.log("IMPLEMENTATION_ADDRESS=", implementation);
        console.log("PROXY_ADMIN_ADDRESS=", proxyAdmin);
        console.log("============================\n");

        vm.stopBroadcast();
    }
} 