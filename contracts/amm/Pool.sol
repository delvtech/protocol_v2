// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import { LP } from "./LP.sol";
import { DateString } from "../libraries/DateString.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TypedFixedPointMathLib, UFixedPoint } from "../libraries/TypedFixedPointMathLib.sol";
import { IMultiToken } from "../interfaces/IMultiToken.sol";
import { SafeCast } from "../libraries/SafeCast.sol";

/// TODO: Downcasting checks
contract Pool is LP {

    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;
    using TypedFixedPointMathLib for UFixedPoint;
    using TypedFixedPointMathLib for uint256;

    uint256 public constant ONE_18 = 1e18;

    /// Trade type the contract support.
    enum TradeType { BUY_PT, SELL_PT, BUY_SHARES }

    /// A percentage commission get charge on every trade & get distributed to LPs.
    /// It is in 18 decimals
    uint256 public tradeFee;

    /// Governance contract that allows to do some administrative operation.
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
    mapping(uint256 => uint256) public timeStretchs;

    // ------------------------------ Events ------------------------------//
    
    /// Emitted when the pool reserves get updated.
    event Sync(uint256 indexed poolId, uint256 bondReserve, uint256 shareReserve);

    /// Emitted when `tradeFee` get updated by the governance contract.
    event TradeFeeUpdated(uint256 oldFee, uint256 newFee);

    /// Emitted event when the bonds get traded.
    event BondsTraded(uint256 indexed poolId, address indexed receiver, TradeType indexed tradeType, uint256 amountIn, uint256 amountOut);

    /// Emitted when the YTs got purchased.
    event YtPurchased(uint256 indexed poolId, address indexed receiver, uint256 amountOfYtMinted, uint256 sharesIn);

    /// Emitted when new poolId get registered with the pool.
    event NewPoolIdRegistered(uint256 indexed poolId);

    
    /// @notice Initialize the contract with below params.
    /// @param _term Address of the YieldAdapter whose PTs and YTs are supported with this Pool.
    /// @param _tradeFee Percentage of fee get deducted during any trade, Should be in 18 decimals
    /// @param _erc20ForwarderCodeHash The hash of the erc20 forwarder contract deploy code.
    /// @param _governanceContract Governance contract address.
    /// @param _erc20ForwarderFactory The factory which is used to deploy the forwarder contracts.
    constructor(
        ITerm _term,
        uint256 _tradeFee,
        bytes32 _erc20ForwarderCodeHash,
        address _governanceContract,
        address _erc20ForwarderFactory
    ) LP(_term, _erc20ForwarderCodeHash, _erc20ForwarderFactory) {
        // Should not be zero.
        require(_governanceContract != address(0), "todo nice errors");

        //----------------Perform some sstore---------------------//
        tradeFee = _tradeFee;
        governanceContract = _governanceContract;
    }

    /// @notice Returns the name of the sub token i.e LP token supported
    ///         by this contract.
    /// @return Returns the name of this token
    function name(uint256 poolId) external view override returns (string memory) {
        return _processString(string(abi.encodePacked("LP",IMultiToken(address(_term)).name(poolId))), poolId);
    }

    /// @notice Returns the symbol of the sub token i.e LP token supported
    ///         by this contract.
    /// @return Returns the symbol of this token
    function symbol(uint256 poolId) external view override returns (string memory) {
        return _processString(string(abi.encodePacked("LP",IMultiToken(address(_term)).symbol(poolId))), poolId);
    }

    /// @notice Used to initialize the reserves of the pool for given poolIds.
    ///         - Initialization of the pool also consider an unaccounted balance of bonds but not shares.
    ///         - It mints corresponding LP token equal to the amount of bonds supply,i.e. `bondsIn`.
    /// @dev    Alice wants to initialize the pool to earn some sweet fee on its
    ///         PT holdings.
    ///         Alice have 120 PTs and 100 DAI while initialization of pool supports
    ///         Tokenized vault shares instead of underlying tokens so she would first
    ///         converts her DAI (base or underlying token) into the TV shares.
    ///         100 DAI --->(Supported Term)---> 100 shares.
    ///         Now Alice can intitalize the pool with 120 PTs as `bondsIn` and 100 as `sharesIn`.
    /// @param  poolId New poolId which will get supported by this pool.
    /// @param  sharesIn Amount of shares used to initialize the reserves.
    /// @param  bondsIn Amount of bonds used to initialize the reserves.
    /// @param  timeStretch No. of seconds in our timescale.
    /// @param  recipient Address which will receive the minted LP tokens.
    /// @return mintedLpTokens No. of minted LP tokens amount for provided `poolIds`.
    function registerPoolId(uint256 poolId, uint256 sharesIn, uint256 bondsIn, uint256 timeStretch, address recipient) external returns(uint256 mintedLpTokens) {
        // Expired PTs are not supported.
        require(poolId > block.timestamp, "todo nice time errors");
        // Should not be already initialized.
        require(totalSupply[poolId] == uint256(0), "todo nice errors");
        // Make sure the timestretch is non-zero.
        require(timeStretch > uint256(0), "todo nice errors");
        // Make sure the provided bondsIn and sharesIn are non-zero values.
        require(sharesIn > 0 && bondsIn > 0, "todo nice errors");
        // Receiver of the LP tokens
        recipient = recipient == address(0) ? msg.sender : recipient;
        // Transfer the bondsIn
        IMultiToken(address(_term)).transferFrom(poolId, msg.sender, address(this), bondsIn);
        // Transfer the sharesIn
        IMultiToken(address(_term)).transferFrom(_UNLOCK_TERM_ID, msg.sender, address(this), sharesIn);
        // Initialize the reserves.
        _update(poolId, _getUnCheckedBondBalance().toUint128(), sharesIn.toUint128(), uint128(0), uint128(0));
        // Mint LP tokens to the recipient.
        _mint(poolId, recipient, mintedLpTokens = bondsIn);
        // Emit events
        emit NewPoolIdRegistered(poolId);
    } 

    //----------------------------------------- Trading functionality ------------------------------------------//

    /// @notice Facilitate the trade of bonds where it can be buy or sell depending on the given trade type.
    /// @param  poolId Expiration timestamp of the bond (,i.e PT).
    /// @param  amount     It represent the amount of asset user wants to spend when the TradeType is `BUY_PT` otherwise it
    ///                    represent the amount of bonds (,i.e. PT) user wants to sell.
    /// @param  amountOut  Minimum expected returns user is willing to accept, If `receivedAmt` is less than it,
    ///                    revert the trade.
    /// @param  receiver   Address which receive the bonds in case of `BUY_PT` or receive underlying token in case of `SELL_PT`.
    /// @param  tradeType  Tells the operation type user wants to perform either BUY_PT or SELL_PT.
    function tradeBonds(
        uint256 poolId,
        uint256 amount,
        uint256 amountOut,
        address receiver,
        TradeType tradeType
    ) external returns(uint256 receivedAmt) {
        // No trade after expiration
        require(poolId > block.timestamp, "Todo nice time error");
        // Should check for the support with the pool.
        require(totalSupply[poolId] > uint256(0) , "todo nice error");
        // Validate that `amount` is non zero.
        require(amount != uint256(0), "nice todo errors");
        // Use `msg.sender` as receiver if the provided receiver is zero address.
        receiver = recevier == address(0) ? msg.sender : receiver;
        // Read the cached reserves for the unlocked shares and bonds ,i.e. PT.
        Reserve memory cachedReserve = reserves[poolId];
        // Execute trade type
        (receivedAmt, changeInShares) = tradeType == TradeType.BUY ? _buyBonds(poolId, amount, cachedReserve) : _sellBonds(poolId, amount, cachedReserve, receiver);
        // Minimum amount check.
        require(receivedAmt >= amountOut, "todo nice errors");
        // When trade type is SELL, funds are already transferred to the receiver to save one extra transfer.
        if (tradeType == TradeType.BUY_PT) {
            // Derive the PT token (bond) address.
            address bondToken = IMultiToken(address(term)).deriveForwarderAddress(poolId);
            // Transfer the bond tokens,i.e PTs to the receiver.
            IERC20(bondToken).safeTransfer(receiver, receivedAmt);
        }
        // TODO: use fixed point addition and subtraction.
        uint128 newShareReserve = tradeType == TradeType.BUY_PT ? cachedReserve.shares + changeInShares.toUint128() : cachedReserve.shares - changeInShares.toUint128();
        // Updated reserves.
        _update(poolId, getBondBalance(poolId), newShareReserve, cachedReserve.bonds, cachedReserve.shares);
        // Emit event for the offchain services.
        emit BondsTraded(poolId, receiver, tradeType, amount, receivedAmt);
    }


    /// @notice Facilitate the purchase of the YT
    /// @param  poolId Expiration timestamp of the bond (,i.e PT) correspond to which YT got minted.
    /// @param  amountOut Minimum No. of YTs buyer is expecting to have after the trade.
    /// @param  recepient Destination at which newly minted YTs got transferred.
    /// @param  maxInput Maximum amount of shares buyer wants to spend on this trade.
    function purchaseYt(uint256 poolId, uint256 amountOut, address recepient, uint256 maxInput) external {
        // No trade after expiration
        require(poolId > block.timestamp, "Todo nice time error");
        // Should check for the support with the pool.
        require(totalSupply[poolId] > uint256(0) , "todo nice error");
        // Validate that `amount` is non zero.
        require(amountOut != uint256(0), "nice todo errors");
        // Use `msg.sender` as recepient if the provided recepient is zero address.
        recepient = recepient == address(0) ? msg.sender : recepient;
        // Read the cached reserves for the unlocked YT and bonds ,i.e. PT.
        uint128 cSharesReserve = reserves[poolId].shares;
        uint128 cBondsReserve = reserves[poolId].bonds;
        // Calculate the shares received when selling `amountOut` PTs.
        uint256 sharesReceived = _sellBondsPreview(amountOut, cSharesReserve, cBondsReserve);
        // Calculate the shares without fee.
        uint256 sharesWithOutFee = _chargeFee(poolId, amountOut, sharesReceived, TradeType.SELL_PT);
        // Convert the shares into underlying.
        uint256 underlyingAmt = term.unlockedSharePrice() * sharesWithOutFee;
        // Make sure user wouldn't end up paying more.
        require(amountOut - underlyingAmt <= maxInput, "todo nice errors");
        // Transfer the remaining underlying token from the buyer.
        IMultiToken(address(term)).transferFrom(_UNLOCK_TERM_ID, msg.sender, address(this), amountOut - underlyingAmt);
        // Buy the PTs and YTs
        (, uint256 yt) = term.lock(
            [_UNLOCK_TERM_ID],
            [amountOut],
            0,
            recepient,
            address(this),
            block.timestamp,
            poolId
        );
         // Updated reserves.  --- TODO change the value of shares reserve.
        _update(poolId, getBondBalance(poolId), cSharesReserve, cBondsReserve, cSharesReserve);
        emit YtPurchased(poolId, recepient, yt, amountOut - underlyingAmt);
    }

    // TODO: Make sure the decimal precision is correct.
    /// @dev Facilitate the purchase of the bonds.
    /// @param  poolId Pool Id supported for the trade.
    /// @param  amount Amount of underlying asset (or base asset) provided to purchase the bonds.
    /// @param  cachedReserve Cached reserve at the time of trade.
    /// @return Amount of bond tokens, trade offers.
    function _buyBonds(uint256 poolId, uint256 amount, Reserve memory cachedReserve) internal returns(uint256 bondsAmountWithOutFee, uint256 changeInShares) {
        // Transfer the funds to the contract
        token.safeTransferFrom(msg.sender, address(this), amount);
        
        // We deposit into the unlocked position of the term in order to calculate
        // the price per share and therefore implied interest rate.
        // This is the step that deposits all value provided into the yield source
        // Note - we need a pointless storage to memory to convince the solidity type checker
        // to understand the type of []
        uint256[] memory empty = new uint256[](0);
        // Deposit the underlying token in to the tokenized vault
        // to get the shares of it.
        (, uint256 changeInShares) = term.lock(
            empty,
            empty,
            amount,
            address(this),
            // There's no PT for this
            address(this),
            0,
            _UNLOCK_TERM_ID
        );
        // Calculate the amount of bond tokens.
        uint128 expectedBondsOut = _buyBondsPreview(
            changeInShares.toUFixedPoint(),
            uint256(cachedReserve.shares).toUFixedPoint(),
            uint256(cachedReserve.bonds).toUFixedPoint()
        );
        // Charge fee on the interest rate offered during the trade.
        bondsAmountWithOutFee = _chargeFee(poolId, uint256(expectedBondsOut), changeInShares, TradeType.BUY_PT);
    }

    // TODO: Make sure the decimal precision is correct.
    /// @dev Facilitate the sell of bond tokens.
    /// It will transfer the underlying token instead of the shares ??
    /// @param  poolId Pool Id supported for the trade.
    /// @param  amount Amount of bonds tokens user wants to sell in given trade.
    /// @param  cachedReserve Cached reserve at the time of trade.
    /// @param  receiver Address which would receive the underlying token.
    /// @return Amount of shares, trade offers.
    function _sellBonds(uint256 poolId, uint256 amount, Reserve memory cachedReserve, address receiver) internal returns(uint256 sharesWithOutFee, uint256 changeInShares ) {
        // Transfer the bonds to the contract
        IMultiToken(address(_term)).transferFrom(poolId, msg.sender, address(this), amount);
        // Sell bonds preview. changeInShares ~ expectedSharesOut in terminology here
        uint256 changeInShares = _sellBondsPreview(amount.toUFixedPoint(), uint256(cachedReserve.shares).toUFixedPoint(), uint256(cachedReserve.bonds).toUFixedPoint());
        // Charge fee on the interest rate offered during the trade.
        sharesWithOutFee = _chargeFee(poolId, changeInShares, amount, TradeType.SELL_PT);
        // Create the arrays for a withdraw from term
        uint256[] memory ids = new uint256[](1);
        ids[0] = _UNLOCK_TERM_ID;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = sharesWithOutFee;
        // Do the withdraw to user account
        term.unlock(receiver, ids, amounts);
    }

    /// @dev Update the reserves after the trade or whenever the LP is minted.
    /// @param  poolId Sub pool Id, Corresponds to it reserves get updated.
    /// @param  bondBalance current holdings of the bond tokens,i.e. PTs of the contract.
    /// @param  sharesBalance current holding of the shares tokens by the contract.
    /// @param  cachedBondReserve Cached reserve of bond tokens.
    /// @param  cachedSharesReserve Cached reserve of shares tokens.
    function _update(uint256 poolId, uint128 bondBalance, uint128 sharesBalance, uint128 cachedBondReserve, uint128 cachedSharesReserve) internal {
        // No need to update and spend gas on SSTORE if reserves haven't changed.
        if (sharesBalance == cachedSharesReserve && bondBalance == cachedBondReserve) return;
        // Update the reserves.
        reserves[poolId].bonds = bondBalance;
        reserves[poolId].shares = sharesBalance;
        emit Sync(poolId, bondBalance, sharesBalance);
    }
    
    /// @dev Charge fee for the trade.
    /// @param poolId Sub pool Id, Corresponds to it fees get updated.
    function _chargeFee(uint256 poolId, uint256 amountOut, uint256 amountIn, TradeType _type) internal returns(uint256) {
        if (_type == TradeType.BUY_PT) {
            uint256 impliedFee = tradeFee.toUFixedPoint().mulDown((amountOut - amountIn).toUFixedPoint()).fromUFixedPoint();
            fees[poolId].feesInBonds += impliedFee.toUint128(); 
            return amountOut - impliedFee;
        } else if (_type == TradeType.SELL_PT) {
            uint256 impliedFee = tradeFee.toUFixedPoint().mulDown((amountIn - amountOut).toUFixedPoint()).fromUFixedPoint();
            fees[poolId].feesInShares += impliedFee.toUint128(); 
            return amountOut - impliedFee;
        }
    }


    /// @notice Return the bond balance of the contract, subtracting the fees from the actual balance.
    /// @param poolId Identifier of the bond token whose balance gets queried.
    function getBondBalance(uint256 poolId) public pure returns(uint128 _bondBalance) {
        return (_getUnCheckedBondBalance(poolId) - uint256(fees[poolId].feesInBonds)).toUint128();
    }

    /// @notice Update the `tradeFee` by the governance contract.
    function updateTradeFee(uint256 newTradeFee) external onlyGovernance {
        emit TradeFeeUpdated(tradeFee, tradeFee = newTradeFee);
    }

    function _getUnCheckedBondBalance(uint256 poolId) internal pure returns(uint256) {
        return IMultiToken(address(term)).balanceOf(poolId, address(this));
    }

    function buyBondsPreview(uint128 sharesIn, uint256 poolId) external view returns(uint128 _expectedBondOut) {
        // Read the cached reserves for the unlocked YT and bonds ,i.e. PT.
        Reserve memory cachedReserve = reserves[poolId];
        return _buyBondsPreview(sharesIn, cachedReserve.shares, cachedReserve.bonds);
    }

    function _buyBondsPreview(
        uint128 sharesIn,
        uint128 sharesReserve,
        uint128 bondsReserve
    ) internal view returns(uint128 _expectedBondOut) {
        // TODO - Access the library to know the amount.
    }

    function _sellBondsPreview(
        uint128 bondsIn,
        uint128 sharesReserve,
        uint128 bondsReserve
    ) internal view returns(uint128 _expectedSharesOut) {
        // TODO - Access the library to know the amount.
    }

    /// @dev Used to create the name and symbol of the LP token using the given `_prefix` and `_sufix`.
    function _processString(string memory _prefix, uint256 suffix) internal pure returns(string memory _generatedString) {
        return DateString.encodeAndWriteTimestamp(_prefix, suffix);
    }

}

