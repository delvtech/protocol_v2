// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.12;

import "../YieldAdapter.sol";
import "../interfaces/IERC4626.sol";

contract ERC4626YieldAdapter is YieldAdapter {
    IERC4626 immutable vault;

    uint256 immutable limit;

    // the amount of erc4626 (assets + shares) held in reserve
    uint256 unlockShares;

    constructor(IERC4626 _vault, uint256 _limit) {
        vault = _vault;
        limit = _limit;
    }

    /// @notice Makes deposit into vault
    function _deposit(ShareState _state)
        internal
        override
        returns (uint256 amountUnderlying, uint256 shares)
    {
        // Get the amount of underlying token "assets" that are to be "deposited"
        amountUnderlying = IERC20(vault.asset()).balanceOf(address(this));

        bool shouldEmulateDeposit = _state == ShareState.Unlocked &&
            amountUnderlying <= limit &&
            vault.previewDeposit(amountUnderlying) <=
            vault.balanceOf(address(this));

        if (shouldEmulateDeposit) {
            // check if funds
            // cache old yearn price or read directly
            // The current underlying is added to the value of all yearn shares
            // in the unlocked series. Shares are minted for the user according
            // to the price implied by that total value divided by the total
            // supply of unlocked shares. The underlying is not deposited, but a
            // check is made that the balance of uninvested token is not more
            // than a max univested token constant. If it is a deposit to the
            // 4626 vault is triggered so that the reserve has a
            // ‘goal_uninvested’ constant amount of underlying left.
            // underlying is added to the value of all shares
            // uint256 totalUnlockShares = unlockShares + amountUnderlying;
            // uint256 price = (unlockShares + amountUnderlying / unlockShares);
            // shares = amountUnderlying * price;
            // unlockShares += (shares + amountUnderlying);
            // // shares are "minted"
            // shares = amountUnderlying *
        } else {
            shares = vault.deposit(amountUnderlying, address(this));
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
