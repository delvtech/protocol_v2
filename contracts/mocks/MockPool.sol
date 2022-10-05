// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "contracts/Pool.sol";

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
    {} // solhint-disable-line no-empty-blocks

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

    uint128 internal _newShareReserves;
    uint128 internal _newBondReserves;
    uint256 internal _tradeBondsOutputAmount;

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
        view
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

    function buyBondsExternal(
        uint256 poolId,
        uint256 amount,
        Reserve memory cachedReserve,
        address receiver
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return super._buyBonds(poolId, amount, cachedReserve, receiver);
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

    function sellBondsExternal(
        uint256 poolId,
        uint256 amount,
        Reserve memory cachedReserve,
        address receiver
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return super._sellBonds(poolId, amount, cachedReserve, receiver);
    }

    event QuoteSaleAndFees(
        uint256 poolId,
        uint256 amount,
        uint128 reserveShares,
        uint128 reserveBonds,
        uint256 pricePerShare
    );

    uint256 internal _quoteSaleAndFees_newShareReserve;
    uint256 internal _quoteSaleAndFees_newBondReserve;
    uint256 internal _quoteSaleAndFees_outputShares;

    function setQuoteSaleAndFeesReturnValues(
        uint256 _newShareReserve,
        uint256 _newBondReserve,
        uint256 _outputShares
    ) external {
        _quoteSaleAndFees_newShareReserve = _newShareReserve;
        _quoteSaleAndFees_newBondReserve = _newBondReserve;
        _quoteSaleAndFees_outputShares = _outputShares;
    }

    function _quoteSaleAndFees(
        uint256 poolId,
        uint256 amount,
        Reserve memory cachedReserve,
        uint256 pricePerShare
    )
        internal
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        emit QuoteSaleAndFees(
            poolId,
            amount,
            cachedReserve.shares,
            cachedReserve.bonds,
            pricePerShare
        );

        return (
            _quoteSaleAndFees_newShareReserve,
            _quoteSaleAndFees_newBondReserve,
            _quoteSaleAndFees_outputShares
        );
    }

    function quoteSaleAndFeesExternal(
        uint256 poolId,
        uint256 amount,
        Reserve memory cachedReserve,
        uint256 pricePerShare
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return
            super._quoteSaleAndFees(
                poolId,
                amount,
                cachedReserve,
                pricePerShare
            );
    }

    function normalize(uint256 input) external view returns (uint256) {
        return super._normalize(input);
    }

    function denormalize(uint256 input) external view returns (uint256) {
        return super._denormalize(input);
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

    function updateExternal(
        uint256 poolId,
        uint128 newBondBalance,
        uint128 newSharesBalance
    ) external {
        return super._update(poolId, newBondBalance, newSharesBalance);
    }

    uint256 internal _tradeCalculationOutput;

    function setTradeCalculationReturnValue(uint256 val) external {
        _tradeCalculationOutput = val;
    }

    // NOTE: we cannot emit an event here since this is a view function.
    // emitting an event is considered modifying state.
    function _tradeCalculation(
        uint256, // expiry
        uint256, // input
        uint256, // shareReserve
        uint256, // bondReserve
        uint256, // pricePerShare
        bool // isBondOut
    ) internal view override returns (uint256) {
        return _tradeCalculationOutput;
    }

    event UpdateOracle(
        uint256 poolId,
        uint256 newShareReserve,
        uint256 newBondReserve
    );

    function _updateOracle(
        uint256 poolId,
        uint256 newShareReserve,
        uint256 newBondReserve
    ) internal override {
        emit UpdateOracle(poolId, newShareReserve, newBondReserve);
    }
}
