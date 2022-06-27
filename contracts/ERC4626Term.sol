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
// Would be good to have a final definition of above ^^
//

contract ERC4626Term is Term {
    IERC4626 public immutable vault;

    uint256 public underlyingReserve;
    uint256 public vaultShareReserve;

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
            underlyingReserve;

        vaultShares = vault.deposit(underlyingDeposited, address(this));
    }

    function _depositUnlocked()
        internal
        returns (uint256 underlyingDeposited, uint256 shares)
    {
        underlyingDeposited =
            token.balanceOf(address(this)) -
            underlyingReserve;

        uint256 impliedUnderlyingReserve = _impliedUnderlyingReserve();
        if (impliedUnderlyingReserve == 0) {
            shares = underlyingDeposited;
        } else {
            shares =
                (underlyingDeposited * totalSupply[UNLOCKED_YT_ID]) /
                impliedUnderlyingReserve;
        }

        uint256 proposedUnderlyingReserve = underlyingReserve +
            underlyingDeposited;

        if (proposedUnderlyingReserve > maxReserve) {
            uint256 issuedVaultShares = vault.deposit(
                proposedUnderlyingReserve - targetReserve,
                address(this)
            );
            underlyingReserve = targetReserve;
            vaultShareReserve += issuedVaultShares;
        } else {
            underlyingReserve = proposedUnderlyingReserve;
        }
    }

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
        uint256 impliedUnderlyingReserve = _impliedUnderlyingReserve();

        // NOTE: Shares MUST be burnt/removed from accounting for term before
        // calling withdraw unlocked.
        uint256 underlyingDue = (_shares * impliedUnderlyingReserve) /
            (_shares + totalSupply[UNLOCKED_YT_ID]);

        if (underlyingDue <= underlyingReserve) {
            underlyingReserve -= underlyingDue;
            token.transferFrom(address(this), _dest, underlyingDue);
        } else {
            uint256 underlyingDueAsVaultShares = (vaultShareReserve *
                underlyingDue) / _vaultShareReserveAsUnderlying();

            if (underlyingDueAsVaultShares > vaultShareReserve) {
                vault.redeem(vaultShareReserve, address(this), address(this));
                token.transferFrom(address(this), _dest, underlyingDue);

                underlyingReserve -= underlyingDue;
                vaultShareReserve = 0;
            } else {
                vault.redeem(underlyingDueAsVaultShares, _dest, address(this));
                underlyingReserve -= underlyingDue;
                vaultShareReserve -= underlyingDueAsVaultShares;
            }
        }
        return underlyingDue;
    }

    function _convert(ShareState _state, uint256 _shares)
        internal
        override
        returns (uint256)
    {
        return
            _state == ShareState.Locked
                ? _convertLocked(_shares)
                : _convertUnlocked(_shares);
    }

    function _convertLocked(uint256 _vaultShares)
        internal
        returns (uint256 shares)
    {
        uint256 vaultSharesAsUnderlying = vault.previewRedeem(_vaultShares);
        shares =
            (vaultSharesAsUnderlying * totalSupply[UNLOCKED_YT_ID]) /
            _impliedUnderlyingReserve();

        vaultShareReserve += _vaultShares;
    }

    function _convertUnlocked(uint256 _shares)
        internal
        returns (uint256 vaultShares)
    {
        uint256 _sharesAsUnderlying = (_shares * _impliedUnderlyingReserve()) /
            totalSupply[UNLOCKED_YT_ID];

        vaultShares = vault.previewWithdraw(_sharesAsUnderlying);

        require(vaultShares <= vaultShareReserve, "not enough vault shares");

        vaultShareReserve -= vaultShares;
    }

    function _underlying(uint256 _shares, ShareState _state)
        internal
        view
        override
        returns (uint256)
    {
        if (_state == ShareState.Locked) {
            return vault.previewRedeem(_shares);
        } else {
            return
                (_shares * _impliedUnderlyingReserve()) /
                totalSupply[UNLOCKED_YT_ID];
        }
    }

    function _vaultShareReserveAsUnderlying()
        internal
        view
        returns (uint256 vaultShareReserveAsUnderlying)
    {
        vaultShareReserveAsUnderlying = vault.previewRedeem(vaultShareReserve);
    }

    function _impliedUnderlyingReserve()
        internal
        view
        returns (uint256 impliedUnderlyingReserve)
    {
        impliedUnderlyingReserve = (underlyingReserve +
            _vaultShareReserveAsUnderlying());
    }

    /// @notice Helper to set reserves using one sstore
    /// @param _newReserveUnderlying The new reserve of underlying
    /// @param _newReserveVaultShares The new reserve of wrapped position shares
    // function _setUnlockedReserves(
    //     uint256 _underlyingReserve,
    //     uint256 _vaultShareReserve
    // ) internal {
    //     underlyingReserve = uint128(_underlyingReserve);
    //     vaultShareReserve = uint128(_vaultShareReserve);
    // }
}
