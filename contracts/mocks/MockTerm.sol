// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../Term.sol";

contract MockTerm is Term {
    uint256 convertReturnValue;
    uint256 depositLeftReturnValue;
    uint256 depositRightReturnValue;
    uint256 withdrawReturnValue;
    uint256 underlyingReturnValue;

    constructor(
        bytes32 _linkerCodeHash,
        address _factory,
        IERC20 _token,
        address _owner
    ) Term(_linkerCodeHash, _factory, _token, _owner) {}

    function setConvertReturnValue(uint256 _value) external {
        convertReturnValue = _value;
    }

    function setDepositReturnValues(uint256 _left, uint256 _right) external {
        depositLeftReturnValue = _left;
        depositRightReturnValue = _left;
    }

    function setWithdrawReturnValue(uint256 _value) external {
        withdrawReturnValue = _value;
    }

    function setUnderlyingReturnValue(uint256 _value) external {
        underlyingReturnValue = _value;
    }

    function setSharesPerExpiry(uint256 assetId, uint256 shares) external {
        sharesPerExpiry[assetId] = shares;
    }

    function setTotalSupply(uint256 assetId, uint256 amount) external {
        totalSupply[assetId] = amount;
    }

    function setUserBalance(
        uint256 assetId,
        address user,
        uint256 amount
    ) external {
        balanceOf[assetId][user] = amount;
    }

    function _convert(ShareState _state, uint256 _shares)
        internal
        override
        returns (uint256)
    {
        return convertReturnValue;
    }

    function _deposit(ShareState _state)
        internal
        override
        returns (uint256, uint256)
    {
        return (depositLeftReturnValue, depositRightReturnValue);
    }

    function _underlying(uint256 _shares, ShareState _state)
        internal
        view
        override
        returns (uint256)
    {
        return underlyingReturnValue;
    }

    function _withdraw(
        uint256 _shares,
        address _dest,
        ShareState _state
    ) internal override returns (uint256) {
        return withdrawReturnValue;
    }

    function releasePTExternal(
        FinalizedState memory finalState,
        uint256 assetId,
        address source,
        uint256 amount
    ) external returns (uint256, uint256) {
        return _releasePT(finalState, assetId, source, amount);
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
