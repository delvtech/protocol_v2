// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../Pool.sol";

contract MockPool is Pool {
    constructor(
        ITerm _term,
        IERC20 _token,
        uint256 _tradeFee,
        bytes32 _erc20ForwarderCodeHash,
        address _governanceContract,
        address _erc20ForwarderFactory
    )
        Pool(
            _term,
            _token,
            _tradeFee,
            _erc20ForwarderCodeHash,
            _governanceContract,
            _erc20ForwarderFactory
        )
    {}

    function setFees(
        uint256 poolId,
        uint128 feeShares,
        uint128 feeBond
    ) external {
        governanceFees[poolId] = CollectedFees(feeShares, feeBond);
    }

    function setTotalSupply(uint256 _poolId, uint256 _amount) external {
        totalSupply[_poolId] = _amount;
    }

    function setReserves(
        uint256 _poolId,
        uint128 _shares,
        uint128 _bonds
    ) external {
        reserves[_poolId].shares = _shares;
        reserves[_poolId].bonds = _bonds;
    }

    uint128 _newShareReserves;
    uint128 _newBondReserves;
    uint256 _tradeBondsOutputAmount;

    function setMockTradeReturnValues(
        uint128 __newShareReserves,
        uint128 __newBondReserves,
        uint256 __tradeBondsOutputAmount
    ) external {
        _newShareReserves = __newShareReserves;
        _newBondReserves = __newBondReserves;
        _tradeBondsOutputAmount = __tradeBondsOutputAmount;
    }

    function _mockTrade()
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (_newShareReserves, _newBondReserves, _tradeBondsOutputAmount);
    }

    event BuyBonds(
        uint256 poolId,
        uint256 amount,
        uint128 reserveShares,
        uint128 reserveBonds,
        address receiver
    );

    function _buyBonds(
        uint256 poolId,
        uint256 amount,
        Reserve memory cachedReserve,
        address receiver
    )
        internal
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        emit BuyBonds(
            poolId,
            amount,
            cachedReserve.shares,
            cachedReserve.bonds,
            receiver
        );
        return _mockTrade();
    }

    event SellBonds(
        uint256 poolId,
        uint256 amount,
        uint128 reserveShares,
        uint128 reserveBonds,
        address receiver
    );

    function _sellBonds(
        uint256 poolId,
        uint256 amount,
        Reserve memory cachedReserve,
        address receiver
    )
        internal
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        emit SellBonds(
            poolId,
            amount,
            cachedReserve.shares,
            cachedReserve.bonds,
            receiver
        );
        return _mockTrade();
    }

    function normalize(uint256 input) external view returns (uint256) {
        return super._normalize(input);
    }

    event InitializeBuffer(uint256 bufferId, uint16 minTime, uint16 maxLength);

    function _initializeBuffer(
        uint256 bufferId,
        uint16 minTime,
        uint16 maxLength
    ) internal override {
        emit InitializeBuffer(bufferId, minTime, maxLength);
    }

    event Mint(uint256 tokenID, address to, uint256 amount);

    function _mint(
        uint256 tokenID,
        address to,
        uint256 amount
    ) internal override {
        emit Mint(tokenID, to, amount);
        super._mint(tokenID, to, amount);
    }

    event Update(
        uint256 poolId,
        uint128 newBondBalance,
        uint128 newSharesBalance
    );

    function _update(
        uint256 poolId,
        uint128 newBondBalance,
        uint128 newSharesBalance
    ) internal override {
        emit Update(poolId, newBondBalance, newSharesBalance);
    }
}
