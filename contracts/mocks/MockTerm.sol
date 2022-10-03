// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { Term, IERC20 } from "contracts/Term.sol";

contract MockTerm is Term {
    constructor(
        bytes32 _linkerCodeHash,
        address _factory,
        IERC20 _token,
        address _owner
    ) Term(_linkerCodeHash, _factory, _token, _owner) {} /* solhint-disable-line no-empty-blocks */

    // ####################
    // ###     lock     ###
    // ####################
    event Lock(
        uint256[] assetIds,
        uint256[] assetAmounts,
        uint256 underlyingAmount,
        bool hasPreFunding,
        address ytDestination,
        address ptDestination,
        uint256 ytBeginDate,
        uint256 expiration
    );

    uint256 internal _lockPrincipalTokensReturnValue;
    uint256 internal _lockYieldTokensReturnValue;

    function setLockValues(uint256 principalTokens, uint256 yieldTokens)
        external
    {
        _lockPrincipalTokensReturnValue = principalTokens;
        _lockYieldTokensReturnValue = yieldTokens;
    }

    function lock(
        uint256[] memory assetIds,
        uint256[] memory assetAmounts,
        uint256 underlyingAmount,
        bool hasPreFunding,
        address ytDestination,
        address ptDestination,
        uint256 ytBeginDate,
        uint256 expiration
    ) external override returns (uint256, uint256) {
        emit Lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );
        return (_lockPrincipalTokensReturnValue, _lockYieldTokensReturnValue);
    }

    // ####################
    // ###   _convert   ###
    // ####################
    uint256 internal _convertReturnValue;

    function setConvertReturnValue(uint256 _value) external {
        _convertReturnValue = _value;
    }

    function _convert(ShareState, uint256)
        internal
        view
        override
        returns (uint256)
    {
        return _convertReturnValue;
    }

    uint256 internal _depositLeftReturnValue;
    uint256 internal _depositRightReturnValue;

    function setDepositReturnValues(uint256 _left, uint256 _right) external {
        _depositLeftReturnValue = _left;
        _depositRightReturnValue = _right;
    }

    function _deposit(ShareState)
        internal
        view
        override
        returns (uint256, uint256)
    {
        return (_depositLeftReturnValue, _depositRightReturnValue);
    }

    uint256 internal _withdrawReturnValue;

    function setWithdrawReturnValue(uint256 _value) external {
        _withdrawReturnValue = _value;
    }

    function _withdraw(
        uint256,
        address,
        ShareState
    ) internal view override returns (uint256) {
        return _withdrawReturnValue;
    }

    uint256 internal _currentPricePerShare;

    // TODO: We may ultimately want to set this value for locked and unlocked.
    function setCurrentPricePerShare(uint256 _price) external {
        _currentPricePerShare = _price;
    }

    function _underlying(uint256 _shares, ShareState)
        internal
        view
        override
        returns (uint256)
    {
        return (_currentPricePerShare * _shares) / one;
    }

    function setFinalizedState(
        uint256 expiry,
        FinalizedState memory finalizedState
    ) external {
        finalizedTerms[expiry] = finalizedState;
    }

    function setSharesPerExpiry(uint256 assetId, uint256 shares) external {
        sharesPerExpiry[assetId] = shares;
    }

    function setTotalSupply(uint256 assetId, uint256 amount) external {
        totalSupply[assetId] = amount;
    }

    function setYieldState(uint256 assetId, YieldState memory yieldState)
        external
    {
        yieldTerms[assetId] = yieldState;
    }

    function setUserBalance(
        uint256 assetId,
        address user,
        uint256 amount
    ) external {
        balanceOf[assetId][user] = amount;
    }

    uint256 internal _depositUnlockedLeftReturnValue;
    uint256 internal _depositUnlockedRightReturnValue;

    event DepositUnlocked(
        uint256 underlyingAmount,
        uint256 ptAmount,
        uint256 ptExpiry,
        address destination
    );

    function setDepositUnlockedReturnValues(uint256 _left, uint256 _right)
        external
    {
        _depositUnlockedLeftReturnValue = _left;
        _depositUnlockedRightReturnValue = _right;
    }

    function depositUnlocked(
        uint256 underlyingAmount,
        uint256 ptAmount,
        uint256 ptExpiry,
        address destination
    ) external override returns (uint256, uint256) {
        emit DepositUnlocked(underlyingAmount, ptAmount, ptExpiry, destination);
        return (
            _depositUnlockedLeftReturnValue,
            _depositUnlockedRightReturnValue
        );
    }

    function createYTExternal(
        address destination,
        uint256 value,
        uint256 totalShares,
        uint256 startTime,
        uint256 expiration
    ) external returns (uint256) {
        return
            super._createYT(
                destination,
                value,
                totalShares,
                startTime,
                expiration
            );
    }

    function releaseAssetExternal(
        uint256 assetId,
        address source,
        uint256 amount
    ) external returns (uint256, uint256) {
        return super._releaseAsset(assetId, source, amount);
    }

    event FinalizeTerm(uint256 expiry);

    function finalizeTermExternal(uint256 expiry)
        external
        returns (FinalizedState memory)
    {
        return super._finalizeTerm(expiry);
    }

    function _finalizeTerm(uint256 expiry)
        internal
        override
        returns (FinalizedState memory finalState)
    {
        emit FinalizeTerm(expiry);
        return FinalizedState({ pricePerShare: 1, interest: 2 });
    }

    event ReleaseUnlocked(address source, uint256 amount);

    function releaseUnlockedExternal(address source, uint256 amount)
        external
        returns (uint256, uint256)
    {
        return super._releaseUnlocked(source, amount);
    }

    function _releaseUnlocked(address source, uint256 amount)
        internal
        override
        returns (uint256, uint256)
    {
        emit ReleaseUnlocked(source, amount);
        return (1, 2);
    }

    event ReleaseYT(
        FinalizedState finalState,
        uint256 assetId,
        address source,
        uint256 amount
    );

    function _releaseYT(
        FinalizedState memory finalState,
        uint256 assetId,
        address source,
        uint256 amount
    ) internal override returns (uint256, uint256) {
        emit ReleaseYT(finalState, assetId, source, amount);
        return (1, 2);
    }

    function releaseYTExternal(
        FinalizedState memory finalState,
        uint256 assetId,
        address source,
        uint256 amount
    ) external returns (uint256, uint256) {
        return super._releaseYT(finalState, assetId, source, amount);
    }

    event ReleasePT(
        FinalizedState finalState,
        uint256 assetId,
        address source,
        uint256 amount
    );

    function releasePTExternal(
        FinalizedState memory finalState,
        uint256 assetId,
        address source,
        uint256 amount
    ) external returns (uint256, uint256) {
        return super._releasePT(finalState, assetId, source, amount);
    }

    function _releasePT(
        FinalizedState memory finalState,
        uint256 assetId,
        address source,
        uint256 amount
    ) internal override returns (uint256, uint256) {
        emit ReleasePT(finalState, assetId, source, amount);
        return (1, 2);
    }

    function mintExternal(
        uint256 tokenID,
        address to,
        uint256 amount
    ) external {
        _mint(tokenID, to, amount);
    }

    function parseAssetIdExternal(uint256 _assetId)
        external
        pure
        returns (
            bool,
            uint256,
            uint256
        )
    {
        return _parseAssetId(_assetId);
    }
}
