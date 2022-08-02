// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "./Term.sol";
import "./MultiToken.sol";
import "./interfaces/ICompoundV3.sol";

/// Docs: https://c3-docs.compound.finance/
contract CompoundV3Term is Term {
    /// address of yieldSource
    ICompoundV3 public immutable yieldSource;

    /// accounts for the balance of "unlocked" underlying for this term
    uint128 private _underlyingReserve;

    /// accounts for the balance of "unlocked" vaultShares for this term
    uint128 private _vaultShareReserve;

    /// upper limit of balance of _underlyingReserve allowed in this contract
    uint256 public immutable maxReserve;

    /// desired amount of underlying
    uint256 public immutable targetReserve;

    constructor(
        ICompoundV3 _yieldSource,
        bytes32 _linkerCodeHash,
        address _factory,
        uint256 _maxReserve,
        address _owner
    )
        Term(
            _linkerCodeHash,
            _factory,
            IERC20(_yieldSource.baseToken()),
            _owner
        )
    {
        yieldSource = _yieldSource;
        maxReserve = _maxReserve;
        targetReserve = _maxReserve / 2;
        token.approve(address(_yieldSource), type(uint256).max);
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
        returns (uint256 shares, uint256 underlying)
    {
        return (0, 0);
    }

    function _depositUnlocked()
        internal
        returns (uint256 shares, uint256 underlying)
    {
        return (0, 0);
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
        return 0;
    }

    function _withdrawUnlocked(uint256 _shares, address _dest)
        internal
        returns (uint256 underlying)
    {
        return 0;
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
        return 0;
    }

    function _convertUnlocked(uint256 _unlockedShares)
        internal
        returns (uint256 lockedShares)
    {
        return 0;
    }

    function _underlying(uint256 _shares, ShareState _state)
        internal
        view
        override
        returns (uint256)
    {
        return 0;
    }
}
