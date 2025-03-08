// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../src/NftMarket2.sol";

// Anvil升级 测试通过
contract UpgradeToNftMarket2Script_Anvil is Script {
    function run() external {
        // Anvil 的默认第一个账户私钥
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        // 部署脚本输出的地址
        address proxy = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
        address token = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
        
        console.log("Starting upgrade from address:", deployer);
        console.log("Proxy address:", proxy);
        console.log("Token address:", token);
        
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