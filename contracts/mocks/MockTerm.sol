// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { Term, IERC20 } from "contracts/Term.sol";

library MockTermCall {
    event DepositUnlocked(
        uint256 underlyingAmount,
        uint256 ptAmount,
        uint256 ptExpiry,
        address destination
    );
}

contract MockTerm is Term {
    constructor(
        bytes32 _linkerCodeHash,
        address _factory,
        IERC20 _token,
        address _owner
    ) Term(_linkerCodeHash, _factory, _token, _owner) {}

    // ####################
    // ###   _convert   ###
    // ####################
    uint256 _convertReturnValue;

    function setConvertReturnValue(uint256 _value) external {
        _convertReturnValue = _value;
    }

    function _convert(ShareState _state, uint256 _shares)
        internal
        view
        override
        returns (uint256)
    {
        return _convertReturnValue;
    }

    // ####################
    // ###   _deposit   ###
    // ####################
    uint256 _depositLeftReturnValue;
    uint256 _depositRightReturnValue;

    function setDepositReturnValues(uint256 _left, uint256 _right) external {
        _depositLeftReturnValue = _left;
        _depositRightReturnValue = _right;
    }

    function _deposit(ShareState _state)
        internal
        view
        override
        returns (uint256, uint256)
    {
        return (_depositLeftReturnValue, _depositRightReturnValue);
    }

    // #####################
    // ###   _withdraw   ###
    // #####################
    uint256 _withdrawReturnValue;

    function setWithdrawReturnValue(uint256 _value) external {
        _withdrawReturnValue = _value;
    }

    function _withdraw(
        uint256 _shares,
        address _dest,
        ShareState _state
    ) internal view override returns (uint256) {
        return _withdrawReturnValue;
    }

    // #######################
    // ###   _underlying   ###
    // #######################
    uint256 _underlyingReturnValue;

    function setUnderlyingReturnValue(uint256 _value) external {
        _underlyingReturnValue = _value;
    }

    function _underlying(uint256 _shares, ShareState _state)
        internal
        view
        override
        returns (uint256)
    {
        return _underlyingReturnValue;
    }

    // ###########################
    // ###   sharesPerExpiry   ###
    // ###########################
    function setSharesPerExpiry(uint256 assetId, uint256 shares) external {
        sharesPerExpiry[assetId] = shares;
    }

    // #######################
    // ###   totalSupply   ###
    // #######################
    function setTotalSupply(uint256 assetId, uint256 amount) external {
        totalSupply[assetId] = amount;
    }

    // #####################
    // ###   balanceOf   ###
    // #####################
    function setUserBalance(
        uint256 assetId,
        address user,
        uint256 amount
    ) external {
        balanceOf[assetId][user] = amount;
    }

    // ###########################
    // ###   depositUnlocked   ###
    // ###########################
    uint256 _depositUnlockedLeftReturnValue;
    uint256 _depositUnlockedRightReturnValue;

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
        emit MockTermCall.DepositUnlocked(
            underlyingAmount,
            ptAmount,
            ptExpiry,
            destination
        );
        return (
            _depositUnlockedLeftReturnValue,
            _depositUnlockedRightReturnValue
        );
    }

    // ######################
    // ###   _releasePT   ###
    // ######################
    function releasePTExternal(
        FinalizedState memory finalState,
        uint256 assetId,
        address source,
        uint256 amount
    ) external returns (uint256, uint256) {
        return _releasePT(finalState, assetId, source, amount);
    }

    // #########################
    // ###   _parseAssetId   ###
    // #########################
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
