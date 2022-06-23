// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "./Term.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IERC20.sol";
import "hardhat/console.sol";

// NOTE: "shares" as referenced here may be conflated with "shares" from the
// yield source. For clarity, "shares" from the yield source are to be called
// "vaultShares" to differentiate. "shares" as accounted for in the element
// protocol are representative of a pro rata ownership of underlying deposits
// and vaultShares inclusive of withheld reserves for both which aid
//
// Would be good to have a direct definition of above ^^

contract ERC4626Term is Term {
    IERC4626 public immutable vault;

    uint128 public unlockedUnderlyingReserve;
    uint128 public unlockedVaultShareReserve;

    uint256 public maxReserve;
    uint256 public targetReserve;

    constructor(
        IERC4626 _vault,
        bytes32 _linkerCodeHash,
        address _factory,
        uint256 _maxReserve
    ) Term(_linkerCodeHash, _factory, IERC20(_vault.asset())) {
        vault = _vault;
        maxReserve = _maxReserve;
        targetReserve = _maxReserve / 2;
        token.approve(address(_vault), type(uint256).max);
    }

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
        returns (uint256 underlyingDeposited, uint256 vaultShares)
    {
        underlyingDeposited =
            token.balanceOf(address(this)) -
            unlockedUnderlyingReserve;

        vaultShares = vault.deposit(amountDeposited, address(this));
    }

    function _depositUnlocked() internal returns (uint256, uint256) {
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = _getUnlockedReserveDetails();

        uint256 underlyingDeposited = token.balanceOf(address(this)) -
            underlyingReserve;

        uint256 shares = (underlyingDeposited * totalSupply[UNLOCKED_YT_ID]) /
            impliedUnderlyingReserve;

        uint256 proposedUnderlyingReserve = underlyingReserve +
            underlyingDeposited;

        if (proposedUnderlyingReserve > maxReserve) {
            uint256 issuedVaultShares = vault.deposit(
                proposedUnderlyingReserve - targetReserve,
                address(this)
            );
            _setUnlockedReserves(
                targetReserve,
                vaultShareReserve + issuedVaultShares
            );
        } else {
            _setUnlockedReserves(proposedUnderlyingReserve, vaultShareReserve);
        }

        return (underlyingDeposited, shares);
    }

    // as we are deciding between locked and unlocked states, "shares" means
    // both vaultShares and shares as per the note on the top of the file
    function _withdraw(
        uint256 _shares,
        address _dest,
        ShareState _state
    ) internal override returns (uint256) {
        return
            _state == ShareState.Locked
                ? _withdrawLocked(_shares, _dest)
                : _withdrawUnlocked(_shares, _dest);
    }

    function _withdrawLocked(uint256 _vaultShares, address _dest)
        internal
        returns (uint256)
    {
        return vault.redeem(_vaultShares, _dest, address(this));
    }

    function _withdrawUnlocked(uint256 _shares, address _dest)
        internal
        returns (uint256)
    {
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = _getUnlockedReserveDetails();

        uint256 underlyingDue = (_shares * impliedUnderlyingReserve) /
            totalSupply[UNLOCKED_YT_ID];

        if (underlyingDue <= underlyingReserve) {
            _setUnlockedReserves(
                underlyingReserve - underlyingDue,
                vaultShareReserve
            );

            token.transferFrom(address(this), _dest, underlyingDue);
        } else {
            uint256 underlyingDueAsVaultShares = (vaultShareReserve *
                underlyingDue) / vaultShareReserveAsUnderlying;

            if (underlyingDueAsVaultShares > vaultShareReserve) {
                vault.redeem(vaultShareReserve, address(this), address(this));
                token.transferFrom(address(this), _dest, underlyingDue);

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

    // TODO rename
    function _underlying(uint256 _amountShares, ShareState)
        internal
        view
        override
        returns (uint256)
    {
        return vault.previewRedeem(_amountShares);
    }

    function _getUnlockedReserveDetails()
        internal
        view
        returns (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        )
    {
        (underlyingReserve, vaultShareReserve) = _getUnlockedReserves();

        vaultShareReserveAsUnderlying = vault.previewRedeem(vaultShareReserve);

        impliedUnderlyingReserve = (underlyingReserve +
            vaultShareReserveAsUnderlying);
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
