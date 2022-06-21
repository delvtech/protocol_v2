// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.12;

import "../YieldAdapter.sol";
import "../interfaces/IERC4626.sol";
import "../interfaces/IERC20.sol";
import "hardhat/console.sol";

contract ERC4626Adapter is YieldAdapter {
    // The ERC4626 vault the protocol wishes to interface with
    IERC4626 public immutable vault;

    // These variables store the token balances of this contract and
    // should be packed by solidity into a single slot.
    // They are used in copmn
    uint128 public unlockedUnderlyingReserve;
    uint128 public unlockedShareReserve;

    // c
    uint256 public maxUnderlyingReserve;

    // amount of underlying we hold in reserve rather than depositing for more
    // efficient deposits of small holders
    uint256 public targetUnderlyingReserve;

    uint256 public immutable SCALE;

    // The reserve limit is a upper bound for deposits and withdrawals which
    // if not met, will make those deposits and withdrawals using the internal
    // cash reserves
    // uint256 public immutable reserveLimit;

    // This is the total amount of reserve deposits
    // uint256 public reserveSupply;

    constructor(IERC4626 _vault, uint256 _targetUnderlyingReserve) {
        vault = _vault;
        targetUnderlyingReserve = _targetUnderlyingReserve;
        maxUnderlyingReserve = _targetUnderlyingReserve * 2;

        IERC20(_vault.asset()).approve(address(_vault), type(uint256).max);
        SCALE = 10**IERC20(_vault.asset()).decimals();
    }

    /// @notice Makes deposit into vault
    function _deposit(ShareState _state)
        internal
        override
        returns (uint256, uint256)
    {
        return
            _state == ShareState.Locked ? _depositLocked() : _depositUnlocked();
    }

    function _depositLocked()
        internal
        returns (uint256 amountDeposited, uint256 mintedShares)
    {
        amountDeposited =
            IERC20(vault.asset()).balanceOf(address(this)) -
            unlockedUnderlyingReserve;

        mintedShares = vault.deposit(amountDeposited, address(this));
    }

    function _depositUnlocked() internal returns (uint256, uint256) {
        // load the current cash reserves of both underlying and shares
        (
            uint256 unlockedUnderlying,
            uint256 unlockedShares
        ) = _getUnlockedReserves();

        // Get the amount deposited
        uint256 amountDeposited = IERC20(vault.asset()).balanceOf(
            address(this)
        ) - unlockedUnderlying;



        // Deposit unlock:
        //
        // 1, give user back lp tokens for value deposited
        // 2, if the value user gave you makes the unlocked underlying greater than max, deposit into yearn,
        // deposit the unlocked underlying + the amount the user added - the target
        //
        // 2.1 over the max - 2 ^^
        // 2.2 under the max - store added user amount to unlocked reserves

        // Withdraw unlock:
        //
        // 1, user tells how many lp shares the want to remove
        // 2, calc the value of those shares as a totalValue of unlockedShares * userShares / totalShares
        //
        // 3.1 if there is enough underlying in the reserve, send amount of underlying to user and update underlying reserve
        // 3.2 if not enough, withdraw enough shares to fulfill user request and leave end balance of underlying at target



        // calculate the shares expected to receive for the amount of underlying
        // deposited
        uint256 calculatedShares = vault.previewDeposit(amountDeposited);

        // if the unlockedShareReserve covers the amount of shares needed, we don't make the
        // deposit in the vault
        if (unlockedShares >= calculatedShares) {
            _setUnlockedReserves(
                unlockedUnderlying + amountDeposited,
                unlockedShares - calculatedShares
            );

            return (amountDeposited, calculatedShares);
        }

        // amount of shares needed
        uint256 neededShares = unlockedShares - calculatedShares;
        // calculated amount of underlying necessary to deposit to produce
        // neededShares shares
        uint256 underlyingToCoverNeededShares = vault.previewMint(neededShares);

        // as the amount of unlockedShares < calculatedShares a deposit must be
        // made to fulfill the calculated shares
        //
        // Doing this we must also be mindful of the state of the underlyingReserve
        // and fill it if necessary

        // variable to hold the amount of shares minted in various contexts
        uint265 mintedShares;

        if (unlockedUnderlying < targetUnderlyingReserve) {
            // if reserves are lower than target, we allocate
            // a portion of the deposit into the reserve

            // amount necessary to fill the target reserve 
            uint256 underlyingNeededToFillTarget = targetUnderlyingReserve -
                unlockedUnderlying;

            if (depositAmount < underlyingNeededToFillTarget) {
                // If the amountDeposited is less than the amount of underlying
                // needed, deposit directly and add shares given to unlockedReserve

                mintedShares = vault.deposit(amountDeposited, address(this));

                _setUnlockedReserves(
                    unlockedUnderlying,
                    unlockedShares + mintedShares
                );
            } else {
                // If the amount deposited is greater than or equal to the
                // underlying needed to fill the reserve, we allocate that
                // portion needed from the depositAmount and whats left is then
                // deposited into the vault

                uint256 remainingDepositAmount = depositAmount -
                    underlyingNeededToFillTarget;

                mintedShares = vault.deposit(
                    remainingDepositAmount,
                    address(this)
                );
            }
        } else {
            // if reserves are at or above target we just directly deposit

            mintedShares = vault.deposit(amountDeposited, address(this));

                _setUnlockedReserves(
                    unlockedUnderlying,
                    unlockedShares + mintedShares
                );

        }

        // uint256 mintedShares = vault.deposit(
        //     unlockedUnderlying + amountDeposited,
        //     address(this)
        // );

        // uint256 userMintedShares = mintedShares;

        // _setUnlockedReserves(
        //     0,
        //     unlockedShares + mintedShares - userMintedShares
        // );

        return (amountDeposited, userMintedShares);
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

    // TODO rename sharesForUnderlying and also provide inverse function
    // underlyingForShares
    function _underlying(uint256 _amountShares, ShareState)
        internal
        view
        override
        returns (uint256)
    {
        return vault.previewRedeem(_amountShares);
    }

    /// @notice Helper to get the reserves with one sload
    /// @return Tuple (reserve underlying, reserve shares)
    function _getUnlockedReserves() internal view returns (uint256, uint256) {
        return (
            uint256(unlockedUnderlyingReserve),
            uint256(unlockedShareReserve)
        );
    }

    /// @notice Helper to set reserves using one sstore
    /// @param _newReserveUnderlying The new reserve of underlying
    /// @param _newReserveShares The new reserve of wrapped position shares
    function _setUnlockedReserves(
        uint256 _newReserveUnderlying,
        uint256 _newReserveShares
    ) internal {
        unlockedUnderlyingReserve = uint128(_newReserveUnderlying);
        unlockedShareReserve = uint128(_newReserveShares);
    }
}
