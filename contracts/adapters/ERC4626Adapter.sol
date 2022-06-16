// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "../YieldAdapter.sol";
import "../interfaces/IERC4626.sol";

contract ERC4626YieldAdapter is YieldAdapter {
    constructor(IERC4626 _yieldSource) YieldAdapter(IERC20(_yieldSource.asset()), address(_yieldSource)) {}

    function _deposit(ShareState) internal override returns (uint256, uint256) {
        return (0, 0);
    }

    function _convert(ShareState, uint256) internal override returns (uint256) {
        return 0;
    }

    /// @return the amount produced
    function _withdraw(
        uint256,
        address,
        ShareState
    ) internal override returns (uint256) {
        return 0;
    }

    /// @return The amount of underlying the input is worth
    function _underlying(uint256, ShareState)
        internal
        view
        override
        returns (uint256)
    {
        return 0;
    }
}
