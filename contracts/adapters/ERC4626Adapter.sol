// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.12;

import "../YieldAdapter.sol";
import "../interfaces/IERC4626.sol";

contract ERC4626YieldAdapter is YieldAdapter {
    IERC4626 immutable vault;

    constructor(IERC4626 _vault) {
        vault = _vault;
    }

    /// @notice Makes deposit into vault
    function _deposit(ShareState _state)
        internal
        override
        returns (uint256 amount, uint256 shares)
    {
        if (_state == ShareState.Unlocked) {
            // todo
            amount = 0;
            shares = 0;
        } else {
            amount = IERC20(vault.asset()).balanceOf(address(this));
            shares = vault.deposit(amount, address(this));
        }
    }

    function _withdraw(
        uint256 _amountShares,
        address _dest,
        ShareState _state
    ) internal override returns (uint256 amountAssets) {
        if (_state == ShareState.Unlocked) {
            // todo
            amountAssets = 0;
        } else {
            amountAssets = vault.redeem(_amountShares, _dest, address(this));
        }
    }

    function _convert(ShareState, uint256) internal override returns (uint256) {
        return 0;
    }

    function _underlying(uint256 _amountShares, ShareState)
        internal
        view
        override
        returns (uint256)
    {
        return vault.previewRedeem(_amountShares);
    }
}
