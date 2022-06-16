// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Simple erc20 contract only allowing owner to mint and burn
contract MockAsset is ERC20 {
    address public owner;

    constructor(uint256 _initialSupply, address _receiver)
        ERC20("MockAssetToken", "MAT")
    {
        owner = msg.sender;
        _mint(_receiver, _initialSupply);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Sender not owner");
        _;
    }

    function mint(uint256 _amount) external onlyOwner {
        _mint(owner, _amount);
    }

    function burn(uint256 _amount) external onlyOwner {
        _burn(msg.sender, _amount);
    }
}
