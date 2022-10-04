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

    // ----------------------- lock ----------------------- //

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

    // ----------------------- unlock ----------------------- //

    event Unlock(address destination, uint256[] assetIds, uint256[] amounts);

    uint256 internal _unlockValue;

    function setUnlockReturnValue(uint256 _value) external {
        _unlockValue = _value;
    }

    function unlockExternal(
        address destination,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) external returns (uint256) {
        return super.unlock(destination, tokenIds, amounts);
    }

    function unlock(
        address destination,
        uint256[] memory assetIds,
        uint256[] memory amounts
    ) public override returns (uint256) {
        emit Unlock({
            destination: destination,
            assetIds: assetIds,
            amounts: amounts
        });

        return _unlockValue;
    }

    // ----------------------- convert ----------------------- //

    event Convert(ShareState shareState, uint256 shares);

    uint256 internal _convertReturnValue;

    function setConvertReturnValue(uint256 _value) external {
        _convertReturnValue = _value;
    }

    function _convert(ShareState shareState, uint256 shares)
        internal
        override
        returns (uint256)
    {
        emit Convert(shareState, shares);
        return _convertReturnValue;
    }

    // ----------------------- _deposit ----------------------- //

    event Deposit(ShareState shareState);

    uint256 internal _depositLeftReturnValue;
    uint256 internal _depositRightReturnValue;

    function setDepositReturnValues(uint256 _left, uint256 _right) external {
        _depositLeftReturnValue = _left;
        _depositRightReturnValue = _right;
    }

    function _deposit(ShareState shareState)
        internal
        override
        returns (uint256, uint256)
    {
        emit Deposit(shareState);
        return (_depositLeftReturnValue, _depositRightReturnValue);
    }

    // ----------------------- _withdraw ----------------------- //

    event Withdraw(uint256 shares, address destination, ShareState shareState);

    function _withdraw(
        uint256 _shares,
        address _destination,
        ShareState _shareState
    ) internal override returns (uint256) {
        emit Withdraw(_shares, _destination, _shareState);
        if (_shareState == ShareState.Locked) {
            return (_shares * _currentPricePerShareLocked) / one;
        } else {
            return (_shares * _currentPricePerShareUnlocked) / one;
        }
    }

    // ----------------------- _underlying ----------------------- //

    uint256 internal _currentPricePerShareLocked;
    uint256 internal _currentPricePerShareUnlocked;

    function setCurrentPricePerShare(uint256 _price, ShareState _shareState)
        external
    {
        if (_shareState == ShareState.Locked) {
            _currentPricePerShareLocked = _price;
        } else {
            _currentPricePerShareUnlocked = _price;
        }
    }

    function _underlying(uint256 _shares, ShareState _shareState)
        internal
        view
        override
        returns (uint256)
    {
        if (_shareState == ShareState.Locked) {
            return (_currentPricePerShareLocked * _shares) / one;
        } else {
            return (_currentPricePerShareUnlocked * _shares) / one;
        }
    }

    // ----------------------- unlockedSharePrice ----------------------- //

    function unlockedSharePrice() external view override returns (uint256) {
        return _currentPricePerShareUnlocked;
    }

    // ----------------------- depositUnlocked ----------------------- //

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
    ) public override returns (uint256, uint256) {
        emit DepositUnlocked(underlyingAmount, ptAmount, ptExpiry, destination);
        return (
            _depositUnlockedLeftReturnValue,
            _depositUnlockedRightReturnValue
        );
    }

    function depositUnlockedExternal(
        uint256 underlyingAmount,
        uint256 ptAmount,
        uint256 ptExpiry,
        address destination
    ) external returns (uint256, uint256) {
        return
            super.depositUnlocked(
                underlyingAmount,
                ptAmount,
                ptExpiry,
                destination
            );
    }

    // ----------------------- _createYT ----------------------- //

    event CreateYT(
        address destination,
        uint256 value,
        uint256 totalShares,
        uint256 startTime,
        uint256 expiration
    );

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

    function _createYT(
        address destination,
        uint256 value,
        uint256 totalShares,
        uint256 startTime,
        uint256 expiration
    ) internal override returns (uint256) {
        emit CreateYT(destination, value, totalShares, startTime, expiration);
        // TODO: There may be a better way to compute the discount going forward.
        return value / 2;
    }

    // ----------------------- _releaseAsset ----------------------- //

    event ReleaseAsset(uint256 assetId, address source, uint256 amount);

    function releaseAssetExternal(
        uint256 assetId,
        address source,
        uint256 amount
    ) external returns (uint256, uint256) {
        return super._releaseAsset(assetId, source, amount);
    }

    function _releaseAsset(
        uint256 assetId,
        address source,
        uint256 amount
    ) internal override returns (uint256, uint256) {
        emit ReleaseAsset(assetId, source, amount);
        return (amount, amount);
    }

    // ----------------------- _finalizeTerm ----------------------- //

    event FinalizeTerm(uint256 expiry);

    function setFinalizedState(
        uint256 expiry,
        FinalizedState memory finalizedState
    ) external {
        finalizedTerms[expiry] = finalizedState;
    }

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

    // ----------------------- _releaseUnlocked ----------------------- //

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

    // ----------------------- _releaseYT ----------------------- //

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

    // ----------------------- _releasePT ----------------------- //

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

    // ----------------------- _parseAssetId ----------------------- //

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

    // ----------------------- setters ----------------------- //

    function mintExternal(
        uint256 tokenID,
        address to,
        uint256 amount
    ) external {
        _mint(tokenID, to, amount);
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
}
