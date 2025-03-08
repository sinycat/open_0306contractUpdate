// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// 具有SetApprovalForAll功能的NFT
contract MyNft is ERC721URIStorage, Ownable {
    uint256 private _nextTokenId;

    constructor() ERC721("MyNft", "MNFT") Ownable(msg.sender) {
        _nextTokenId = 1;
    }

    // 铸造NFT的函数，增加tokenURI参数
    function mint(address to, string memory tokenURI) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        _nextTokenId += 1;
        return tokenId;
    }
} 