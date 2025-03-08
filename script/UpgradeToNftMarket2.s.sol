// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../src/NftMarket2.sol";

// Sepolia升级合约 测试通过
contract UpgradeToNftMarket2Script is Script {
    function run() external {
       
        // 从 .env 文件读取私钥和合约地址
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // 直接使用 vm.envAddress 读取地址
        address proxy = vm.envAddress("PROXY_ADDRESS");
        address token = vm.envAddress("TOKEN_ADDRESS");
        
        console.log("Starting upgrade from address:", deployer);
        console.log("Proxy address:", proxy);
        console.log("Token address:", token);
        
        // 检查权限
        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        console.log("Proxy Admin address:", proxyAdmin);
        console.log("Current Implementation:", Upgrades.getImplementationAddress(proxy));
        
        vm.startBroadcast(deployerPrivateKey);

        // 升级到 NftMarket2
        Upgrades.upgradeProxy(
            proxy,
            "NftMarket2.sol",
            abi.encodeCall(NftMarket2.initialize, (token)),
            deployer
        );

        address newImplementation = Upgrades.getImplementationAddress(proxy);
        require(newImplementation != address(0), "Upgrade failed: new implementation is zero address");

        console.log("\n==== Upgrade Successful! ====");
        console.log("NEW_IMPLEMENTATION_ADDRESS=", newImplementation);
        console.log("=========================\n");

        vm.stopBroadcast();
    }
} 