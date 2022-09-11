// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../Term.sol";

contract MockTerm is Term {
    constructor(
        bytes32 _linkerCodeHash,
        address _factory,
        IERC20 _token,
        address _owner
    ) Term(_linkerCodeHash, _factory, _token, _owner) {}

    uint256 convertVal;
    uint256 depositVal1;
    uint256 depositVal2;
    uint256 underlyingVal;
    uint256 withdrawVal;

    function _convert(ShareState _state, uint256 _shares)
        internal
        override
        returns (uint256)
    {
        return convertVal;
    }

    function setConvertReturnValue(uint256 val) external {
        convertVal = val;
    }

    function _deposit(ShareState _state)
        internal
        override
        returns (uint256, uint256)
    {
        return (depositVal1, depositVal2);
    }

    function setDepositReturnValues(uint256 val1, uint256 val2) external {
        depositVal1 = val1;
        depositVal2 = val2;
    }

    function _underlying(uint256 _shares, ShareState _state)
        internal
        view
        override
        returns (uint256)
    {
        return underlyingVal;
    }

    function setUnderlyingReturnValue(uint256 val) external {
        underlyingVal = val;
    }

    function _withdraw(
        uint256 _shares,
        address _dest,
        ShareState _state
    ) internal override returns (uint256) {
        return withdrawVal;
    }

    function setWithdrawReturnValue(uint256 val) external {
        withdrawVal = val;
    }

    function parseAssetIdExternal(uint256 _assetId)
        external
        view
        returns (
            bool,
            uint256,
            uint256
        )
    {
        return _parseAssetId(_assetId);
    }
}
