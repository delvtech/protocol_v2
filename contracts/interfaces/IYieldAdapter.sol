// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

interface IYieldAdapter {
    /// @return tuple (shares minted, amount underlying used)
    function deposit() external returns (uint256, uint256);

    /// @return the amount produced
    function withdraw(
        uint256,
        address,
        uint256
    ) external returns (uint256);

    /// @return The amount of underlying the input is worth
    function underlying(uint256) external view returns (uint256);
}
