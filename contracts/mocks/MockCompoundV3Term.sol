// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../CompoundV3Term.sol";

contract MockCompoundV3Term is CompoundV3Term {
    constructor(
        address _yieldSource,
        bytes32 _linkerCodeHash,
        address _factory,
        uint256 _maxReserve,
        address _owner
    )
        CompoundV3Term(
            _yieldSource,
            _linkerCodeHash,
            _factory,
            _maxReserve,
            _owner
        )
    {} // solhint-disable-line no-empty-blocks

    function setReservesExternal(
        uint256 _newUnderlyingReserve,
        uint256 _newYieldShareReserve
    ) external {
        _setCacheInfo(_newUnderlyingReserve, _newYieldShareReserve);
    }

    function getUnderlyingReserve() public view returns (uint128) {
        return _underlyingReserve;
    }

    function getYieldShareReserve() public view returns (uint128) {
        return _yieldShareReserve;
    }

    function yieldSharesAsUnderlying(uint256 shares)
        public
        view
        returns (uint256)
    {
        return ((shares * yieldSource.balanceOf(address(this))) /
            _yieldSharesIssued);
    }

    function getYieldSharesIssued() public returns (uint256) {
        return (_yieldSharesIssued);
    }

    function underlyingAsYieldShares(uint256 underlying)
        public
        view
        returns (uint256)
    {
        return ((underlying * _yieldSharesIssued) /
            yieldSource.balanceOf(address(this)));
    }
}
