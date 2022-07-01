// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import { LP } from "./LP.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TypedFixedPointMathLib, UFixedPoint } from "../libraries/TypedFixedPointMathLib.sol";

contract Pool is LP {

    using SafeERC20 for IERC20;
    using TypedFixedPointMathLib for UFixedPoint;
    using TypedFixedPointMathLib for uint256;

    uint256 public constant ONE_18 = 1e18;

    /// Trade type the contract support.
    enum TradeType { BUY, SELL}

    /// The no of seconds in timescale;
    uint256 public immutable timescale;

    /// A percentage commission get charge on every trade & get distributed to LPs.
    /// It is in 18 decimals
    uint256 public tradeFee;

    /// No. of seconds in a year.
    uint256 public constant ONE_YEAR_IN_SECONDS = 31556952;

    /// Governance contrac that allows to do some administrative operation.
    address public immutable governanceContract;

    /// Fees collected
    struct CollectedFees {
        /// Fees in terms of shares.
        uint128 feesInShares;

        /// Fees in terms of bonds.
        uint128 feesInBonds;
    }

    /// Data structure to keep the oracle details in cheap storage format.
    struct Oracle {
        /// Last calculated cumulative price of the bond.
        uint112 bondPriceCumulativeLast;
        /// Last calculated cumulative price of the share.
        uint112 sharesPriceCumulativeLast;
        /// Last recorded timestamp when prices are updated.
        uint32 blockTimestampLast;
    }

    /// Mapping to keep track of TWAP oracle details corresponds to `poolId`.
    mapping(uint256 => Oracle) public oracles;

    /// Mapping to keep track of fee collection corresponds to `poolId`.
    mapping(uint256 => CollectedFees) public fees;
    
    event Sync(uint256 indexed poolId, uint256 bondReserve, uint256 shareReserve);

    /// Emitted when `tradeFee` get updated by the governance contract.
    event TradeFeeUpdated(uint256 oldFee, uint256 newFee);

    /// Emitted event when the bonds get traded.
    event BondsTraded(uint256 indexed poolId, address indexed receiver, TradeType indexed tradeType, uint256 amountIn, uint256 amountOut);

    
    /// @notice Initialize the contract with below params.
    /// @param _underlyingToken Underlying token that get invested into the yield source.
    /// @param _term Address of the YieldAdapter whose PTs and YTs are supported with this Pool.
    /// @param _poolIds Expiration times supported by the pool.
    /// @param _timestretch Time stretch for the pool.
    /// @param _tradeFee Percentage of fee get deducted during any trade.
    /// @param _name Prefix of the name of the LP token.
    /// @param _symbol Prefix of the symbol of the LP token.
    /// @param _erc20ForwarderCodeHash The hash of the erc20 forwarder contract deploy code.
    /// @param _governanceContract Governance contract address.
    /// @param _erc20ForwarderFactory The factory which is used to deploy the forwarder contracts.
    constructor(
        IERC20 _underlyingToken,
        ITerm _term,
        uint256[] _poolIds,
        uint256 _timeStretch,
        uint256 _tradeFee,
        string memory _name,
        string memory _symbol,
        bytes32 _erc20ForwarderCodeHash,
        address _governanceContract,
        address _erc20ForwarderFactory
    ) LP(_underlyingToken, _term, _erc20ForwarderCodeHash, _erc20ForwarderFactory) {
        // Should not be zero.
        require(_governanceContract != address(0), "todo nice errors");
        tradeFee = _tradeFee;
        timescale = _timeStretch * ONE_YEAR_IN_SECONDS;
        governanceContract = _governanceContract;

        for (uint256 i = 0; i < _poolIds.length; i++) {
            // Making sure that timescale is sufficient.
            require(_poolIds[i] - block.timestamp < _timescale, "todo nice erros");
            name[_poolIds[i]] = _processString(_name, _poolIds[i]);
            symbol[_poolIds[i]] = _processString(_symbol, _poolIds[i]);
        }

    }

    // TODO
    function _processString(string memory _prefix, uint256 suffix) internal returns(string memory _generatedString) {
        //
    } 


    /// @notice Facilitate the trade of bonds where it can be buy or sell depending on the given trade type.
    /// @param  poolId Expiration timestamp of the bond (,i.e PT).
    /// @param  amount            It represent the amount of asset user wants to spend when the TradeType is `BUY` otherwise it
    ///                           represent the amount of bonds (,i.e. PT) user wants to sell.
    /// @param  expectedAmountOut Minimum expected returns user is willing to accept, If `receivedAmt` is less than that
    ///                           then revert the trade.
    /// @param  receiver          Address which receive the bonds in case of `BUY` or receive underlying token in case of `SELL`.
    /// @param  tradeType         Tells the operation type user wants to perform either BUY or SELL.
    function tradeBonds(
        uint256 poolId,
        uint256 amount,
        uint256 expectedAmountOut,
        address receiver,
        TradeType tradeType
    ) external returns(uint256 receivedAmt) {
        // No minting after expiration
        require(poolId > block.timestamp, "Todo nice time error");
        // Validate that `amount` is non zero.
        require(amount != uint256(0), "nice todo errors");
        // Use `msg.sender` as receiver if the provided receiver is zero address.
        receiver = recevier == address(0) ? msg.sender : receiver;
        // Read the cached reserves for the unlocked YT and bonds ,i.e. PT.
        Reserve memory cachedReserve = reserves[poolId];
        // Execute trade type
        receivedAmt = tradeType == TradeType.BUY ? _buyBonds(amount, cachedReserve) : _sellBonds();
        // Minimum amount check.
        require(receivedAmt >= expectedAmountOut, "todo nice errors");
        // Derive the PT token (bond) address.
        address bondToken = IMultiToken(address(term)).deriveForwarderAddress(poolId);
        // Transfer the bond tokens,i.e PTs to the receiver.
        IERC20(bondToken).safeTransfer(receiver, receivedAmt);
        // Updated TWAP oracle.
        _update(poolId, getBondBalance(poolId), getSharesBalance(_UNLOCK_TERM_ID), cachedReserve.bonds, cachedReserve.shares);
        // Emit event for the offchain services.
        emit BondsTraded(poolId, receiver, tradeType, amount, receivedAmt);
    }


    function _buyBonds(uint256 amount, Reserve memory cachedReserve) internal returns(uint256) {
        // Transfer the funds to the contract
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Converting the amount from underlying token decimals to 18 decimal precision.
        uint256 _fixedPointAmt = _normalize(amount, decimals);
        
        // We deposit into the unlocked position of the term in order to calculate
        // the price per share and therefore implied interest rate.
        // This is the step that deposits all value provided into the yield source
        // Note - we need a pointless storage to memory to convince the solidity type checker
        // to understand the type of []
        uint256[] memory empty = new uint256[](0);
        // depositedShares == YT minted 
        (uint256 depositedShares, ) = term.lock(
            empty,
            empty,
            amount,
            address(this),
            // There's no PT for this
            address(this),
            0,
            _UNLOCK_TERM_ID
        );
        uint128 expectedBondsOut = _buyBondsPreview(uint128(depositedShares), cachedReserve.shares, cachedReserve.bonds);
        
        // Deduct fees
        uint256 chargedTradeFee = UFixedPoint.unwrap(
            UFixedPoint.wrap(_normalize(uint256(expectedBondsOut), decimals)).mulDown(UFixedPoint.wrap(tradeFee))
            ) / 100;
        expectedBondsOut -= chargedTradeFee;
        feesInBonds += chargedTradeFee;

        // Return the quoted bonds amount.
        return expectedBondsOut; 
    }

    function _sellBonds() internal returns(uint256) {

    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint256 poolId, uint128 bondBalance, uint128 shareBalance, uint128 bondReserve, uint128 shareReserve) private {
        require(bondBalance <= uint128(-1) && shareBalance <= uint128(-1), "todo nice errors");
        Oracle storage _o = oracles[poolId];
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - _o.blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && bondReserve != 0 && shareReserve != 0) {
            // * never overflows, and + overflow is desired
            _o.bondPriceCumulativeLast   += shareReserve * timeElapsed / bondReserve;
            _o.sharesPriceCumulativeLast += bondReserve * timeElapsed / shareReserve;
        }
        reserves[poolId] = Reserve { shares: shareBalance, bonds: bondBalance };
        _o.blockTimestampLast = blockTimestamp;
        emit Sync(poolId, bondBalance, shareBalance);
    }

    function getBondBalance(uint256 poolId) public pure returns(uint128 _bondBalance) {
        // Todo - safety checks for the downcasting.
        return uint128(IMultiToken(address(term)).balanceOf(poolId, address(this)) - uint256(fees[poolId].feesInBonds));
    }

    function getSharesBalance(uint256 poolId) public pure returns(uint128 _sharesBalance) {
        // Todo - safety checks for the downcasting.
        return uint128(IMultiToken(address(term)).balanceOf(poolId, address(this)) - uint256(fees[poolId].feesInShares));
    }

    function buyBondsPreview(uint128 sharesIn, uint256 poolId) external view returns(uint128 _expectedBondOut) {
        // Read the cached reserves for the unlocked YT and bonds ,i.e. PT.
        Reserve memory cachedReserve = reserves[poolId];
        return _buyBondsPreview(sharesIn, cachedReserve.shares, cachedReserve.bonds);
    }

    /// @notice Update the `tradeFee` by the governance contract.
    function updateTradeFee(uint256 newTradeFee) external onlyGovernance {
        emit TradeFeeUpdated(tradeFee, tradeFee = newTradeFee);
    }

    function _buyBondsPreview(
        uint128 sharesIn,
        uint128 sharesReserve,
        uint128 bondsReserve
    ) internal view returns(uint128 _expectedBondOut) {
        // TODO - Access the library to know the amount.
    }

    function _normalize(uint256 amt, uint256 fromDecimals) internal returns(uint256) {
        return amt * ONE_18 / fromDecimals;
    }

}

