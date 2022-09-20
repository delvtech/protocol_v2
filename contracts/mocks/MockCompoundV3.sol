// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "contracts/interfaces/ICompoundV3.sol";
import "contracts/interfaces/IERC20.sol";

contract MockCompoundV3 is ICompoundV3 {
    IERC20 internal _baseToken;
    mapping(address => uint256) internal _balances;

    constructor(IERC20 baseTokenAddress) {
        _baseToken = baseTokenAddress;
    }

    // supply an amount of an asset to this contract
    function supply(address asset, uint256 amount) external override {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        // assume assets 1-1 with baseToken
        _balances[msg.sender] += amount;
    }

    // withdraw an amount of an asset to this contract
    function withdraw(address asset, uint256 amount) external override {
        // assume assets 1-1 with baseToken
        _balances[msg.sender] -= amount;
        IERC20(asset).transfer(msg.sender, amount);
    }

    // withdraw an amount of an asset to this contract to a specified address
    function withdrawTo(
        address to,
        address asset,
        uint256 amount
    ) external override {
        // assume assets 1-1 with baseToken
        _balances[msg.sender] -= amount;
        IERC20(asset).transfer(to, amount);
    }

    // returns the address of the base token
    function baseToken() external view override returns (address) {
        return address(_baseToken);
    }

    // returns the baseToken balance of a user
    function balanceOf(address owner) public view override returns (uint256) {
        return _balances[owner];
    }
}
