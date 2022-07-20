// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "./Term.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IERC20.sol";
import "./MultiToken.sol";

import "hardhat/console.sol";

contract ERC4626Term is Term {
    IERC4626 public immutable vault;

    uint128 private _underlyingReserve;
    uint128 private _vaultShareReserve;

    uint256 public immutable maxReserve;
    uint256 public immutable targetReserve;

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
        token.approve(address(this), type(uint256).max);
    }

    function underlyingReserve() public view returns (uint256) {
        return uint256(_underlyingReserve);
    }

    function vaultShareReserve() public view returns (uint256) {
        return uint256(_vaultShareReserve);
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
        returns (uint256 vaultShares, uint256 underlyingDeposited)
    {
        (uint256 underlyingReserve, , , ) = reserveDetails();
        underlyingDeposited =
            token.balanceOf(address(this)) -
            underlyingReserve;

        vaultShares = vault.deposit(underlyingDeposited, address(this));
    }

    function _depositUnlocked()
        internal
        returns (uint256 shares, uint256 underlyingDeposited)
    {
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        underlyingDeposited =
            token.balanceOf(address(this)) -
            underlyingReserve;

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

            _setReserves(targetReserve, vaultShareReserve + issuedVaultShares);
        } else {
            _setReserves(proposedUnderlyingReserve, vaultShareReserve);
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
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        // NOTE: Shares MUST be burnt/removed from accounting for term before
        // calling withdraw unlocked.
        uint256 underlyingDue = (_shares * impliedUnderlyingReserve) /
            (_shares + totalSupply[UNLOCKED_YT_ID]);

        if (underlyingDue <= underlyingReserve) {
            _setReserves(underlyingReserve - underlyingDue, vaultShareReserve);
            token.transferFrom(address(this), _dest, underlyingDue);
        } else {
            if (underlyingDue > vaultShareReserveAsUnderlying) {
                uint256 underlyingRedeemed = vault.redeem(
                    vaultShareReserve,
                    address(this),
                    address(this)
                );

                token.transferFrom(address(this), _dest, underlyingDue);
                _setReserves(
                    underlyingReserve - (underlyingDue - underlyingRedeemed),
                    0
                );
            } else {
                uint256 withdrawnVaultShares = vault.withdraw(
                    underlyingDue,
                    _dest,
                    address(this)
                );
                _setReserves(
                    underlyingReserve,
                    vaultShareReserve - withdrawnVaultShares
                );
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
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            ,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        shares =
            (vaultSharesAsUnderlying * totalSupply[UNLOCKED_YT_ID]) /
            impliedUnderlyingReserve;

        _setReserves(underlyingReserve, vaultShareReserve + _vaultShares);
    }

    function _convertUnlocked(uint256 _shares)
        internal
        returns (uint256 vaultShares)
    {
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            ,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        // NOTE: Shares MUST be burnt/removed from accounting for term before
        // calling convert unlocked.
        uint256 sharesAsUnderlying = (_shares * impliedUnderlyingReserve) /
            (_shares + totalSupply[UNLOCKED_YT_ID]);

        vaultShares = vault.previewWithdraw(sharesAsUnderlying);

        // TODO Should we consider adjustment of underlyingReserve when this is exceeded??
        require(vaultShares <= vaultShareReserve, "not enough vault shares");

        _setReserves(underlyingReserve, vaultShareReserve - vaultShares);
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
            (, , , uint256 impliedUnderlyingReserve) = reserveDetails();
            return
                (_shares * impliedUnderlyingReserve) /
                totalSupply[UNLOCKED_YT_ID];
        }
    }

    function reserveDetails()
        public
        view
        returns (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        )
    {
        (underlyingReserve, vaultShareReserve) = _getReserves();

        vaultShareReserveAsUnderlying = vault.previewRedeem(vaultShareReserve);

        impliedUnderlyingReserve = (underlyingReserve +
            vaultShareReserveAsUnderlying);
    }

    function _getReserves() internal view returns (uint256, uint256) {
        return (uint256(_underlyingReserve), uint256(_vaultShareReserve));
    }

    function _setReserves(
        uint256 _newUnderlyingReserve,
        uint256 _newVaultShareReserve
    ) internal {
        _underlyingReserve = uint128(_newUnderlyingReserve);
        _vaultShareReserve = uint128(_newVaultShareReserve);
    }
}
