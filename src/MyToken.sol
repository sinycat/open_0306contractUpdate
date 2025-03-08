// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// 具有transferWithCallback功能的ERC20
interface ITokenReceiver {
    function tokensReceived(
        address operator,
        address from,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}

contract MyToken is ERC20, Ownable {
    constructor() ERC20("MyToken", "MTK") Ownable(msg.sender) {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function transferWithCallback(
        address operator,
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        require(to != address(0), "Transfer to zero address");
        require(balanceOf(operator) >= amount, "Insufficient balance");
        require(to.code.length > 0, "Recipient must be a contract");
        
        // 先进行转账
        _transfer(operator, to, amount);
        
        // 再调用回调
        try ITokenReceiver(to).tokensReceived(
            operator,
            msg.sender,
            amount,
            data
        ) returns (bool success) {
            require(success, "Callback failed");
            return true;
        } catch {
            revert("Recipient does not implement ITokenReceiver");
        }
    }
}