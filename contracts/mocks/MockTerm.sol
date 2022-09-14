// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../Term.sol";

contract MockTerm is Term {
    uint256 convertReturnValue;
    uint256 depositLeftReturnValue;
    uint256 depositRightReturnValue;
    uint256 withdrawReturnValue;
    uint256 currentPricePerShare;

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

    // TODO: We may ultimately want to set this value for locked and unlocked.
    function setCurrentPricePerShare(uint256 _value) external {
        currentPricePerShare = _value;
    }

    function setFinalizedState(
        uint256 assetId,
        FinalizedState memory finalState
    ) external {
        finalizedTerms[assetId] = finalState;
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

    function setYieldState(uint256 assetId, YieldState memory yieldState)
        external
    {
        yieldTerms[assetId] = yieldState;
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
        return (currentPricePerShare * _shares) / one;
    }

    function _withdraw(
        uint256 _shares,
        address _dest,
        ShareState _state
    ) internal override returns (uint256) {
        return withdrawReturnValue;
    }

    function finalizeTermExternal(uint256 expiry)
        external
        returns (FinalizedState memory)
    {
        return _finalizeTerm(expiry);
    }

    function releaseUnlockedExternal(address source, uint256 amount)
        external
        returns (uint256, uint256)
    {
        return _releaseUnlocked(source, amount);
    }

    function releaseYTExternal(
        FinalizedState memory finalState,
        uint256 assetId,
        address source,
        uint256 amount
    ) external returns (uint256, uint256) {
        return _releaseYT(finalState, assetId, source, amount);
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
