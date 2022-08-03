// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "./Term.sol";
import "./MultiToken.sol";
import "./interfaces/ICompoundV3.sol";

/// Docs: https://c3-docs.compound.finance/
contract CompoundV3Term is Term {
    ICompoundV3 public immutable yieldSource;

    // TODO Combine these into single SLOAD?
    uint256 public yieldSharesIssued;

    uint128 private _underlyingReserve;
    uint128 private _yieldShareReserve;

    uint256 public immutable maxReserve;
    uint256 public immutable targetReserve;

    constructor(
        address _yieldSource,
        bytes32 _linkerCodeHash,
        address _factory,
        uint256 _maxReserve,
        address _owner
    )
        Term(
            _linkerCodeHash,
            _factory,
            IERC20(ICompoundV3(_yieldSource).baseToken()),
            _owner
        )
    {
        yieldSource = ICompoundV3(_yieldSource);
        maxReserve = _maxReserve;
        targetReserve = _maxReserve / 2;
        token.approve(address(_yieldSource), type(uint256).max);
    }

    function underlyingReserve() public view returns (uint256) {
        return uint256(_underlyingReserve);
    }

    function yieldShareReserve() external view returns (uint256) {
        return uint256(_yieldShareReserve);
    }

    function _deposit(ShareState _state)
        internal
        override
        returns (uint256, uint256)
    {
        return
            _state == ShareState.Locked ? _depositLocked() : _depositUnlocked();
    }

    /// Compound shares are non-constant meaning they directly represent claim
    /// on underlying. We have to manage this in a constant manner by tracking
    /// the underlyingDeposited
    function _depositLocked()
        internal
        returns (uint256 shares, uint256 underlying)
    {
        underlying = token.balanceOf(address(this)) - underlyingReserve();

        uint256 accruedUnderlying = yieldSource.balanceOf(address(this));
        yieldSource.supply(address(token), underlying);

        if (accruedUnderlying == 0) {
            yieldSharesIssued += underlying;
            return (underlying, underlying);
        }

        shares = (yieldSharesIssued * underlying) / accruedUnderlying;
        yieldSharesIssued += shares;
    }

    function _depositUnlocked()
        internal
        returns (uint256 shares, uint256 underlying)
    {
        (
            uint256 underlyingReserve_,
            uint256 yieldShareReserve_,
            ,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = _reserveDetails();

        underlying = token.balanceOf(address(this)) - underlyingReserve_;

        if (impliedUnderlyingReserve == 0) {
            shares = underlying;
        } else {
            shares =
                (underlying * totalSupply[UNLOCKED_YT_ID]) /
                impliedUnderlyingReserve;
        }

        uint256 proposedUnderlyingReserve = underlyingReserve_ + underlying;

        if (proposedUnderlyingReserve > maxReserve) {
            uint256 underlyingSupplied = proposedUnderlyingReserve -
                targetReserve;

            uint256 underlyingSuppliedAsYieldShares = (yieldSharesIssued *
                underlyingSupplied) / accruedUnderlying;

            yieldSource.supply(address(token), underlyingSupplied);
            yieldSharesIssued += underlyingSuppliedAsYieldShares;

            _setReserves(
                targetReserve,
                yieldShareReserve_ + underlyingSuppliedAsYieldShares
            );
        } else {
            _setReserves(proposedUnderlyingReserve, yieldShareReserve_);
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

    function _withdrawLocked(uint256 _shares, address _dest)
        internal
        returns (uint256 underlying)
    {
        uint256 lockedSharesAsUnderlying = yieldSharesAsUnderlying(_shares);
        yieldSource.withdrawTo(_dest, address(token), lockedSharesAsUnderlying);
        yieldSharesIssued -= _shares;

        // TODO Is it over engineered to do an underflow check and withdraw yieldShareIssued if so?
    }

    function _withdrawUnlocked(uint256 _shares, address _dest)
        internal
        returns (uint256 underlying)
    {
        (
            uint256 underlyingReserve_,
            uint256 yieldShareReserve_,
            uint256 yieldShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = _reserveDetails();

        underlying =
            (_shares * impliedUnderlyingReserve) /
            (_shares + totalSupply[UNLOCKED_YT_ID]);

        if (underlying <= underlyingReserve_) {
            _setReserves(underlyingReserve_ - underlying, yieldShareReserve_);
            token.transfer(_dest, underlying);
        } else {
            if (underlying > yieldShareReserveAsUnderlying) {
                yieldSource.withdraw(
                    address(token),
                    yieldShareReserveAsUnderlying
                );

                token.transfer(_dest, underlying);
                yieldSharesIssued -= yieldShareReserve_;
                _setReserves(
                    underlyingReserve_ -
                        (underlying - yieldShareReserveAsUnderlying),
                    0
                );
            } else {
                uint256 underlyingAsYieldShares = (yieldSharesIssued *
                    underlying) / accruedUnderlying;

                yieldSource.withdrawTo(_dest, address(token), underlying);

                // TODO Is it over engineered to do an underflow check and withdraw yieldShareIssued if so?
                yieldSharesIssued -= underlyingAsYieldShares;
                _setReserves(
                    underlyingReserve_,
                    yieldShareReserve_ - underlyingAsYieldShares
                );
            }
        }
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

    function _convertLocked(uint256 _lockedShares)
        internal
        returns (uint256 unlockedShares)
    {
        (
            uint256 underlyingReserve_,
            uint256 yieldShareReserve_,
            ,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = _reserveDetails();

        uint256 lockedSharesAsUnderlying = (accruedUnderlying * _lockedShares) /
            yieldSharesIssued;

        unlockedShares =
            (lockedSharesAsUnderlying * totalSupply[UNLOCKED_YT_ID]) /
            impliedUnderlyingReserve;

        _setReserves(underlyingReserve_, yieldShareReserve_ + _lockedShares);
    }

    function _convertUnlocked(uint256 _unlockedShares)
        internal
        returns (uint256 lockedShares)
    {
        (
            uint256 underlyingReserve_,
            uint256 yieldShareReserve_,
            ,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = _reserveDetails();

        uint256 unlockedSharesAsUnderlying = (_unlockedShares *
            impliedUnderlyingReserve) /
            (_unlockedShares + totalSupply[UNLOCKED_YT_ID]);

        lockedShares =
            (yieldSharesIssued * unlockedSharesAsUnderlying) /
            accruedUnderlying;

        require(lockedShares <= yieldShareReserve_, "not enough vault shares");

        _setReserves(underlyingReserve_, yieldShareReserve_ - lockedShares);
    }

    function _underlying(uint256 _shares, ShareState _state)
        internal
        view
        override
        returns (uint256)
    {
        if (_state == ShareState.Locked) {
            return yieldSharesAsUnderlying(_shares);
        } else {
            (, , , uint256 impliedUnderlyingReserve, ) = _reserveDetails();
            return
                (_shares * impliedUnderlyingReserve) /
                totalSupply[UNLOCKED_YT_ID];
        }
    }

    function _reserveDetails()
        internal
        view
        returns (
            uint256 underlyingReserve_,
            uint256 yieldShareReserve_,
            uint256 yieldShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        )
    {
        (underlyingReserve_, yieldShareReserve_) = (
            uint256(_underlyingReserve),
            uint256(_yieldShareReserve)
        );

        accruedUnderlying = yieldSource.balanceOf(address(this));

        yieldShareReserveAsUnderlying =
            (accruedUnderlying * yieldShareReserve_) /
            yieldSharesIssued;

        impliedUnderlyingReserve = (underlyingReserve_ +
            yieldShareReserveAsUnderlying);
    }

    function underlyingAsYieldShares(uint256 underlying)
        public
        view
        returns (uint256 yieldShares)
    {
        yieldShares =
            (yieldSharesIssued * yieldShares) /
            yieldSource.balanceOf(address(this));
    }

    function yieldSharesAsUnderlying(uint256 yieldShares)
        public
        view
        returns (uint256 underlying)
    {
        underlying =
            (yieldSource.balanceOf(address(this)) * underlying) /
            yieldSharesIssued;
    }

    function _setReserves(
        uint256 _newUnderlyingReserve,
        uint256 _newYieldShareReserve
    ) internal {
        _underlyingReserve = uint128(_newUnderlyingReserve);
        _yieldShareReserve = uint128(_newYieldShareReserve);
    }
}
