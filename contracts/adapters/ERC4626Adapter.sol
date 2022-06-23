// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "../Term.sol";
import "../interfaces/IERC4626.sol";
import "../interfaces/IERC20.sol";
import "hardhat/console.sol";

contract ERC4626Adapter is Term {
    // The ERC4626 vault the protocol wishes to interface with
    IERC4626 public immutable vault;

    uint128 public unlockedUnderlyingReserve;
    uint128 public unlockedVaultShareReserve;

    uint256 public maxReserve;
    uint256 public targetReserve;

    constructor(
        IERC4626 _vault,
        uint256 _maxReserve,
        bytes32 _linkerCodeHash,
        address _factory,
        IERC20 _token
    ) Term(_linkerCodeHash, _factory, _token) {
        vault = _vault;
        maxReserve = _maxReserve;
        targetReserve = _maxReserve / 2;
        IERC20(_vault.asset()).approve(address(_vault), type(uint256).max);
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
            uint256 underlyingReserve,
            uint256 vaultShareReserve
        ) = _getUnlockedReserves();

        // Get the amount deposited
        uint256 underlyingDeposited = IERC20(vault.asset()).balanceOf(
            address(this)
        ) - underlyingReserve;

        // unlockTokens - infinitely large erc20 tokens in these, the unlockToken corresponds to
        // ownership of the combination of unlocked u8nderlying and unlocked yearn shares e.g usdc & yusdc

        // unlockTokensSupply - can be retrieved from term - unlockTokensSupplyBy     // UNLOCKED_YT_ID

        // Deposit unlock:
        //
        // 1, give user back lp tokens (shares) for value deposited - pricePerShare * yea
        // 2, if the value user gave you makes the unlocked underlying greater than max, deposit into yearn,
        // deposit the unlocked underlying + the amount underlying the user added - the target
        //
        // 2.1 over the max - 2 ^^
        // 2.2 under the max - store added user amount to unlocked reserves

        // numUnlockTokens = amountToDeposit * totalSupply / totalValue : totalValue = unlockedUnderlying + previewRedeem(unlockedYearnShares):
        // accumulation fn
        //
        //
        uint256 vaultShareReserveAsUnderlying = vault.previewRedeem(
            vaultShareReserve
        );

        // gets total amount of underlying including the underelying value of
        // vaultShares at current market price
        //
        uint256 impliedUnderlyingReserve = (underlyingReserve +
            vaultShareReserveAsUnderlying);
        uint256 unlockTokensToBeMinted = (underlyingDeposited *
            totalSupply[UNLOCKED_YT_ID]) / impliedUnderlyingReserve;

        // summate the reserve and amount of underlying deposited
        uint256 positedUnderlyingReserve = underlyingReserve +
            underlyingDeposited;

        // If the totalUnderlying is greater than the max reserve the contract
        // allows we fill the underlying reserve
        if (positedUnderlyingReserve > maxReserve) {
            // The amount of mintedShares should be marginally less than the
            // calculatedShares amount. This is because the amount deposited
            // here should always be marginally less than the depositAmount
            uint256 issuedVaultShares = vault.deposit(
                positedUnderlyingReserve - targetReserve,
                address(this)
            );

            // As we are depositing the current underlying reserve +
            // amountDeposited less the target, we can set the reserve to the
            // target
            _setUnlockedReserves(
                targetReserve,
                vaultShareReserve + issuedVaultShares
            );
        } else {
            _setUnlockedReserves(positedUnderlyingReserve, vaultShareReserve);
        }
        return (underlyingDeposited, unlockTokensToBeMinted);
    }

    function _withdraw(
        uint256 _amountUnlockTokens,
        address _dest,
        ShareState _state
    ) internal override returns (uint256) {
        return
            _state == ShareState.Locked
                ? _withdrawLocked(_amountUnlockTokens, _dest)
                : _withdrawUnlocked(_amountUnlockTokens, _dest);
    }

    function _withdrawLocked(uint256 _amountUnlockTokens, address _dest)
        internal
        returns (uint256)
    {
        return vault.redeem(_amountUnlockTokens, _dest, address(this));
    }

    // Withdraw unlock:
    //
    // 1, user tells how many unlocke shares they want to remove
    // 2, calc the value of those shares as a totalValue of unlockedShares * userShares / totalUnlockTokens
    //
    // 3.1 if there is enough underlying in the reserve, send amount of underlying to user and update underlying reserve
    // 3.2 if not enough, withdraw enough shares to fulfill user request and leave end balance of underlying at target
    function _withdrawUnlocked(uint256 _amountUnlockTokens, address _dest)
        internal
        returns (uint256)
    {
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve
        ) = _getUnlockedReserves();

        // uint256 numer = amountToDeposit * totalSupply[UNLOCKED_YT_ID]
        // uint256 underlyingForYearnShares = vault.previewRedeem(unlockedYearnShares);
        // uint256 unlockTokensToBeMinted = numer / (unlockedUnderlying + underlyingForYearnShares);

        // (userClaimPercentage) * (unlockedUnderlying + redeemableAmount(unlockYearnShares))
        //
        // uint256 underlyingForYearnShares = vault.previewRedeem(unlockYearnShares);

        // uint256 vaultShareReserveAsUnderlying = vault.previewRedeem(vaultShareReserve);

        // uint256 unlockReservesAsUnderlying =  unlockedUnderlying + underlyingForYearnShares // vault.previewRedeem(unlockYearnShares)

        uint256 vaultShareReserveAsUnderlying = vault.previewRedeem(
            vaultShareReserve
        );

        // // gets total amount of underlying including the underelying value of
        // // vaultShares at current market price
        // //
        uint256 impliedUnderlyingReserve = (underlyingReserve +
            vaultShareReserveAsUnderlying);

        uint256 underlyingDue = (_amountUnlockTokens *
            impliedUnderlyingReserve) / totalSupply[UNLOCKED_YT_ID];

        if (underlyingDue <= underlyingReserve) {
            _setUnlockedReserves(
                underlyingReserve - underlyingDue,
                vaultShareReserve
            );
            IERC20(vault.asset()).transferFrom(
                address(this),
                _dest,
                underlyingDue
            );
        } else {
            uint256 underlyingDueAsVaultShares = (vaultShareReserve *
                underlyingDue) / vaultShareReserveAsUnderlying; // amount of shares

            if (underlyingDueAsVaultShares > vaultShareReserve) {
                // The returned amount of underlying redeem from vault shares
                // ought to be accounted for in vaultShareReserveAsUnderlying
                vault.redeem(vaultShareReserve, address(this), address(this));

                IERC20(vault.asset()).transferFrom(
                    address(this),
                    _dest,
                    underlyingDue
                );

                _setUnlockedReserves(
                    impliedUnderlyingReserve - underlyingDue,
                    0
                );
            } else {
                vault.redeem(underlyingDueAsVaultShares, _dest, address(this));
                _setUnlockedReserves(
                    underlyingReserve - underlyingDue,
                    vaultShareReserve - underlyingDueAsVaultShares
                );
            }
        }

        return underlyingDue;
    }

    // converts unlockedTokens to lockedTokens
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
    /// @return Tuple (reserve underlying, reserve vault shares)
    function _getUnlockedReserves() internal view returns (uint256, uint256) {
        return (
            uint256(unlockedUnderlyingReserve),
            uint256(unlockedVaultShareReserve)
        );
    }

    /// @notice Helper to set reserves using one sstore
    /// @param _newReserveUnderlying The new reserve of underlying
    /// @param _newReserveVaultShares The new reserve of wrapped position shares
    function _setUnlockedReserves(
        uint256 _newReserveUnderlying,
        uint256 _newReserveVaultShares
    ) internal {
        unlockedUnderlyingReserve = uint128(_newReserveUnderlying);
        unlockedVaultShareReserve = uint128(_newReserveVaultShares);
    }
}
