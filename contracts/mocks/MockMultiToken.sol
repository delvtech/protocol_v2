// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "../MultiToken.sol";

contract MockMultiToken is MultiToken {
    constructor(bytes32 _linkerCodeHash, address _factory)
        MultiToken(_linkerCodeHash, _factory)
    {}

    function setNameAndSymbol(
        uint256 tokenId,
        string calldata _name,
        string calldata _symbol
    ) external {
        name[tokenId] = _name;
        symbol[tokenId] = _symbol;
    }

    function setBalance(
        uint256 tokenId,
        address who,
        uint256 amount
    ) external {
        balanceOf[tokenId][who] = amount;
    }
}
