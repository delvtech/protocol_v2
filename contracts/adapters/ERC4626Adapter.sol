// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.12;

import "../YieldAdapter.sol";
import "../interfaces/IERC4626.sol";
import "../interfaces/IERC20.sol";
import "hardhat/console.sol";

contract ERC4626Adapter is Term {
    // The ERC4626 vault the protocol wishes to interface with
    IERC4626 public immutable vault;

    // These variables store the token balances of this contract and
    // should be packed by solidity into a single slot.
    // They are used in copmn
    uint128 public unlockedUnderlyingReserve;
    uint128 public unlockedVaultShareReserve;

    //
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

    constructor(IERC4626 _vault, uint256 _maxUnderlyingReserve) {
        vault = _vault;
        maxUnderlyingReserve = _maxUnderlyingReserve;
        targetUnderlyingReserve = _maxUnderlyingReserve / 2;

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
            uint256 unlockedYearnShares
        ) = _getUnlockedReserves();

        // Get the amount deposited
        uint256 amountDeposited = IERC20(vault.asset()).balanceOf(
            address(this)
        ) - unlockedUnderlying;



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

        uint256 numer = amountToDeposit * totalSupply[UNLOCKED_YT_ID]
        uint256 underlyingForYearnShares = vault.previewRedeem(unlockedYearnShares);
        uint256 unlockTokensToBeMinted = numer / (unlockedUnderlying + underlyingForYearnShares);

        // summate the reserve and amount of underlying deposited
        uint256 totalUnderlying = unlockedUnderlying + amountDeposited;

        // If the totalUnderlying is greater than the max reserve the contract
        // allows we fill the underlying reserve
        if (totalUnderlying > maxUnderlyingReserve) {
            // The amount of mintedShares should be marginally less than the
            // calculatedShares amount. This is because the amount deposited
            // here should always be marginally less than the depositAmount
           uint256 mintedShares = vault.deposit(
                totalUnderlying - targetUnderlyingReserve,
                address(this)
            );

            // As we are depositing the current underlying reserve +
            // amountDeposited less the target, we can set the reserve to the
            // target
            _setUnlockedReserves(targetUnderlyingReserve, unlockedShares + mintedShares);
       } else {
            _setUnlockedReserves(totalUnderlying, unlockedShares);
        }

        return (amountDeposited, unlockTokensToBeMinted);
   }

    function _withdraw(
        uint256 _amountShares,
        address _dest,
        ShareState _state
    ) internal override returns (uint256) {
        return
            _state == ShareState.Locked
                ? _withdrawLocked()
                : _withdrawUnlocked();
    }

    function _withdrawLocked(uint256 _amountShares, address _dest)
        internal
        override
        returns (uint256)
    {
        return vault.redeem(_amountShares, _dest, address(this));
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
        override
        returns (uint256)
    {

        (
            uint256 unlockedUnderlying,
            uint256 unlockedYearnShares
        ) = _getUnlockedReserves();

        // uint256 numer = amountToDeposit * totalSupply[UNLOCKED_YT_ID]
        // uint256 underlyingForYearnShares = vault.previewRedeem(unlockedYearnShares);
        // uint256 unlockTokensToBeMinted = numer / (unlockedUnderlying + underlyingForYearnShares);

        // (userClaimPercentage) * (unlockedUnderlying + redeemableAmount(unlockYearnShares))
        //
        uint256 underlyingForYearnShares = vault.previewRedeem(unlockYearnShares);


        uint256 unlockReservesAsUnderlying =  unlockedUnderlying + underlyingForYearnShares // vault.previewRedeem(unlockYearnShares)
        uint256 underlyingDue = _amountUnlockTokens * unlockReservesAsUnderlying / (totalSupply[UNLOCKED_YT_ID])

        if (underlyingDue <= unlockedUnderlying) {
            _setUnlockedReserves(totalUnderlying - underlyingDue, unlockedYearnShares);
            IERC20().transferFrom(address(this), _dest, underlyingDue);
        } else {
            uint256 neededYearnSharesForWithdraw = unlockYearnShares * underlyingDue / underlyingForYearnShares // amount of shares

            if (neededYearnSharesForWithdraw > unlockYearnShares) {
                uint256 underlyingToCoverNeededShares = vault.withdraw(unlockYearnShares, address(this)) // withdraw to all shares to this contract
                IERC20().transferFrom(address(this), _dest, underlyingDue);
                _setUnlockedReserves(totalUnderlying + underlyingToCoverNeededShares - underlyingDue, 0);
            } else {
                vault.withdraw(neededYearnSharesForWithdraw, _dest);
                _setUnlockedReserves(totalUnderlying - underlyingDue, unlockedYearnShares - neededYearnSharesForWithdraw);
            }
        }

        return underlyingDue;
    }

    // converts unlockedTokens to lockedTokens
    function _convert(ShareState, uint256) internal override returns (uint256) {
        return
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
