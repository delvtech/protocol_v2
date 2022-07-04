// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import { LP } from "./LP.sol";
import { DateString } from "../libraries/DateString.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TypedFixedPointMathLib, UFixedPoint } from "../libraries/TypedFixedPointMathLib.sol";

contract Pool is LP {

    using SafeERC20 for IERC20;
    using TypedFixedPointMathLib for UFixedPoint;
    using TypedFixedPointMathLib for uint256;

    uint256 public constant ONE_18 = 1e18;

    /// Trade type the contract support.
    enum TradeType { BUY, SELL}

    /// A percentage commission get charge on every trade & get distributed to LPs.
    /// It is in 18 decimals
    uint256 public tradeFee;

    /// Boolean flag to check whether the pool is already initialized or not.
    bool public isInitialized;

    /// Governance contrac that allows to do some administrative operation.
    address public immutable governanceContract;

    /// Fees collected
    struct CollectedFees {
        /// Fees in terms of shares.
        uint128 feesInShares;

        /// Fees in terms of bonds.
        uint128 feesInBonds;
    }

    /// Mapping to keep track of fee collection corresponds to `poolId`.
    mapping(uint256 => CollectedFees) public fees;

    /// The no of seconds in timescale per poolId;
    mapping(uint256 => uint256) public immutable timeStretchs;
    
    event Sync(uint256 indexed poolId, uint256 bondReserve, uint256 shareReserve);

    /// Emitted when `tradeFee` get updated by the governance contract.
    event TradeFeeUpdated(uint256 oldFee, uint256 newFee);

    /// Emitted event when the bonds get traded.
    event BondsTraded(uint256 indexed poolId, address indexed receiver, TradeType indexed tradeType, uint256 amountIn, uint256 amountOut);

    
    /// @notice Initialize the contract with below params.
    /// @param _term Address of the YieldAdapter whose PTs and YTs are supported with this Pool.
    /// @param _poolIds Expiration times supported by the pool.
    /// @param _timestretch Time stretch for the pool.
    /// @param _tradeFee Percentage of fee get deducted during any trade.
    /// @param _erc20ForwarderCodeHash The hash of the erc20 forwarder contract deploy code.
    /// @param _governanceContract Governance contract address.
    /// @param _erc20ForwarderFactory The factory which is used to deploy the forwarder contracts.
    constructor(
        ITerm _term,
        uint256[] _poolIds,
        uint256[] _timeStretch,
        uint256 _tradeFee,
        bytes32 _erc20ForwarderCodeHash,
        address _governanceContract,
        address _erc20ForwarderFactory
    ) LP(_term, _erc20ForwarderCodeHash, _erc20ForwarderFactory) {
        // Should not be zero.
        require(_governanceContract != address(0), "todo nice errors");
        // Should `_timeStretch` and `poolIds` array have equal length.
        require(_poolIds.length == _timeStretch.length, "todo nice errors");

        //----------------Perform some sstore---------------------
        tradeFee = _tradeFee;
        governanceContract = _governanceContract;

        for (uint256 i = 0; i < _poolIds.length; i++) {
            // No support for the expired Term.
            require(_poolIds[i] > block.timestamp, "todo nice erros");
            name[_poolIds[i]] = _processString(string(abi.encodePacked("LP",IMultiToken(address(_term)).name(_poolIds[i]))), _poolIds[i]);
            symbol[_poolIds[i]] = _processString(string(abi.encodePacked("LP",IMultiToken(address(_term)).symbol(_poolIds[i]))), _poolIds[i]);
            timeStretchs[poolIds[i]] = _timeStretch[i]; 
        }
    }


    /// @notice Used to initialize the reserves of the pool for given poolIds.
    /// @dev    Make sure that it can only be called once.
    /// @param  poolIds Array of poolId whose reserve get initialize.
    /// @return _mintedLpTokens Array of minted LP tokens amount for provided `poolIds`.
    function initialize(uint256[] poolIds, address[] recipient) external returns(uint256[] _mintedLpTokens) {
        // Revert when pool is already initialized with reserves.
        require(!isInitialized, "todo nice errors");

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
        // Should check for the support with the pool.
        require(timeStretchs[poolId] > 0, "todo nice error");
        // Validate that `amount` is non zero.
        require(amount != uint256(0), "nice todo errors");
        // Use `msg.sender` as receiver if the provided receiver is zero address.
        receiver = recevier == address(0) ? msg.sender : receiver;
        // Read the cached reserves for the unlocked YT and bonds ,i.e. PT.
        Reserve memory cachedReserve = reserves[poolId];
        // Execute trade type
        receivedAmt = tradeType == TradeType.BUY ? _buyBonds(amount, cachedReserve) : _sellBonds(amount, cachedReserve);
        // Minimum amount check.
        require(receivedAmt >= expectedAmountOut, "todo nice errors");
        // Derive the PT token (bond) address.
        address bondToken = IMultiToken(address(term)).deriveForwarderAddress(poolId);
        // Transfer the bond tokens,i.e PTs to the receiver.
        IERC20(bondToken).safeTransfer(receiver, receivedAmt);
        // Updated reserves.
        _update(poolId, getBondBalance(poolId), getSharesBalance(_UNLOCK_TERM_ID), cachedReserve.bonds, cachedReserve.shares);
        // Emit event for the offchain services.
        emit BondsTraded(poolId, receiver, tradeType, amount, receivedAmt);
    }

    function _update(uint256 poolId, uint128 bondBalance, uint128 sharesBalance, uint128 cachedBondReserve, uint128 cachedSharesReserve) internal {
        // No need to update and spend gas on SSTORE if reserves haven't changed.
        if (sharesBalance == cachedSharesReserve && bondBalance == cachedBondReserve) return;

        // Update the reserves.
        reserves[poolId].bonds = bondBalance;
        reserves[poolId].shares = sharesBalance;
        emit Sync(poolId, bondBalance, sharesBalance);
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
        
        // TODO: Deduct fees
        
        // uint256 chargedTradeFee = UFixedPoint.unwrap(
        //     UFixedPoint.wrap(_normalize(uint256(expectedBondsOut), decimals)).mulDown(UFixedPoint.wrap(tradeFee))
        //     ) / 100;
        // expectedBondsOut -= chargedTradeFee;
        // feesInBonds += chargedTradeFee;

        // Return the quoted bonds amount.
        return expectedBondsOut; 
    }

    function _sellBonds(uint256 amount, Reserve memory cachedReserve) internal returns(uint256) {

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

    /// @dev Used to create the name and symbol of the LP token using the given `_prefix` and `_sufix`.
    function _processString(string memory _prefix, uint256 suffix) internal pure returns(string memory _generatedString) {
        return DateString.encodeAndWriteTimestamp(_prefix, suffix);
    }

}

