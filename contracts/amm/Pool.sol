// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import "./LP.sol";
import "../libraries/FixedPoint.sol";
import "../interfaces/IMultiToken.sol";
import "../interfaces/ITerm.sol";

/// TODO: Downcasting checks
contract Pool is LP {
    using TypedFixedPointMathLib for uint256;
    // This lets us call internal functions on uint256
    using this for uint256;

    uint256 public constant ONE_18 = 1e18;

    /// Trade type the contract support.
    enum TradeType {
        BUY_PT,
        SELL_PT,
        BUY_SHARES
    }

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

    /// Sub Pool specific details.
    struct SubPoolParameters {
        /// The no of seconds in timescale.
        uint32 timestretch;
        /// Price per share at the time of initialization.
        uint224 mu;
    }

    /// Mapping to keep track of fee collection corresponds to `poolId`.
    mapping(uint256 => CollectedFees) public fees;

    /// Sub pool parameters;
    mapping(uint256 => SubPoolParameters) public parameters;

    // ------------------------------ Events ------------------------------//

    /// Emitted when the pool reserves get updated.
    event Sync(
        uint256 indexed poolId,
        uint256 bondReserve,
        uint256 shareReserve
    );

    /// Emitted when `tradeFee` get updated by the governance contract.
    event TradeFeeUpdated(uint256 oldFee, uint256 newFee);

    /// Emitted event when the bonds get traded.
    event BondsTraded(
        uint256 indexed poolId,
        address indexed receiver,
        TradeType indexed tradeType,
        uint256 amountIn,
        uint256 amountOut
    );

    /// Emitted when the YTs got purchased.
    event YtPurchased(
        uint256 indexed poolId,
        address indexed receiver,
        uint256 amountOfYtMinted,
        uint256 sharesIn
    );

    /// Emitted when new poolId get registered with the pool.
    event NewPoolIdRegistered(uint256 indexed poolId);

    /// Modifier to verify whether the msg.sender is governance contract or not.
    modifier onlyGovernance() {
        require(msg.sender != governanceContract, "todo nice errors");
        _;
    }

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
    function name(uint256 poolId)
        external
        view
        override
        returns (string memory)
    {
        return (string(abi.encodePacked("LP: ", term.name(poolId))));
    }

    /// @notice Returns the symbol of the sub token i.e LP token supported
    ///         by this contract.
    /// @return Returns the symbol of this token
    function symbol(uint256 poolId)
        external
        view
        override
        returns (string memory)
    {
        return (string(abi.encodePacked("LP: ", term.symbol(poolId))));
    }

    /// @notice Used to initialize the reserves of the pool for given poolIds.
    ///         - Initialization of the pool also consider an unaccounted balance of bonds but not shares.
    ///         - It mints corresponding LP token equal to the amount of bonds supply,i.e. `bondsIn`.
    /// @dev    Alice wants to initialize the pool to earn some sweet fee on its
    ///         PT holdings.
    ///         Alice has 120 PTs and 100 DAI while initialization of pool supports
    ///         Tokenized vault shares instead of underlying tokens so she would first
    ///         converts her DAI (base or underlying token) into the TV shares.
    ///         100 DAI --->(Supported Term)---> 100 shares.
    ///         Now Alice can init the pool with 120 PTs as `bondsIn` and 100 as `sharesIn`.
    /// @param  poolId New poolId which will get supported by this pool, equal to bond expiry
    /// @param  sharesIn Amount of tokens used to initialize the reserves.
    /// @param  bondsIn Amount of bonds used to initialize the reserves.
    /// @param  timeStretch No. of seconds in our timescale.
    /// @param  recipient Address which will receive the minted LP tokens.
    /// @return mintedLpTokens No. of minted LP tokens amount for provided `poolIds`.
    function registerPoolId(
        uint256 poolId,
        uint256 amount,
        uint256 bondsIn,
        uint32 timeStretch,
        address recipient
    ) external returns (uint256 mintedLpTokens) {
        // Expired PTs are not supported.
        require(poolId > block.timestamp, "todo nice time errors");
        // Should not be already initialized.
        require(totalSupply[poolId] == uint256(0), "todo nice errors");
        // Make sure the timestretch is non-zero.
        require(timeStretch > uint32(0), "todo nice errors");
        // Make sure the provided bondsIn and amount are non-zero values.
        require(amount > 0 && bondsIn > 0, "todo nice errors");
        // Transfer the bondsIn
        term.transferFrom(poolId, msg.sender, address(this), bondsIn);
        // Transfer tokens from the user
        token.transferFrom(msg.sender, address(this), amount);
        // Make a deposit to the unlocked shares in the term for the user
        // The implied initial share price [ie mu] can be calculated using this
        uint256[] memory empty = new uint256[](0);
        // Deposit the underlying token in to the tokenized vault
        // to get the shares of it.
        (, uint256 sharesMinted) = term.lock(
            empty,
            empty,
            amount,
            address(this),
            // There's no PT for this
            address(this),
            0,
            _UNLOCK_TERM_ID
        );
        // We want to store the mu as an 18 point fraction
        uint256 mu = (sharesMinted._normalize()) /
            // Initialize the reserves.
            _update(poolId, uint128(bondsIn), uint128(sharesMinted));

        // Add the timestretch into the mapping corresponds to the poolId.
        parameters[poolId] = SubPoolParameters(timeStretch, uint224(mu));
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
    ) external returns (uint256 receivedAmt) {
        // No trade after expiration
        require(poolId > block.timestamp, "Todo nice time error");
        // Validate that `amount` is non zero.
        require(amount != uint256(0), "nice todo errors");
        // Read the cached reserves for the unlocked shares and bonds ,i.e. PT.
        Reserve memory cachedReserve = reserves[poolId];
        // Should check for the support with the pool.
        require(
            cachedReserve.shares != uint128(0) &&
                cachedReserve.bonds != uint128(0),
            "todo nice error"
        );
        uint256 changeInShares;
        uint256 changeInBonds;
        // Execute trade type
        (receivedAmt, changeInShares, changeInBonds) = tradeType ==
            TradeType.BUY_PT
            ? _buyBonds(poolId, amount, cachedReserve)
            : _sellBonds(poolId, amount, cachedReserve, receiver);
        // Minimum amount check.
        require(receivedAmt >= amountOut, "todo nice errors");
        // When trade type is SELL, funds are already transferred to the receiver to save one extra transfer.
        if (tradeType == TradeType.BUY_PT) {
            // Transfer the bond tokens,i.e PTs to the receiver.
            IMultiToken(address(term)).transferFrom(
                poolId,
                address(this),
                receiver,
                receivedAmt
            );
        }
        // TODO: use fixed point addition and subtraction.
        // Below is ~ (newShareReserve, newBondReserve) but using the already declared memoory variable to reduce cost.
        (changeInShares, changeInBonds) = tradeType == TradeType.BUY_PT
            ? (
                uint256(cachedReserve.shares) + changeInShares,
                uint256(cachedReserve.bonds) - changeInBonds
            )
            : (
                uint256(cachedReserve.shares) - changeInShares,
                uint256(cachedReserve.bonds) + changeInBonds
            );
        // Updated reserves.
        _update(poolId, changeInBonds.toUint128(), changeInShares.toUint128());
        // Emit event for the offchain services.
        emit BondsTraded(poolId, receiver, tradeType, amount, receivedAmt);
    }

    /// @notice Facilitate the purchase of the YT
    /// @param  poolId Expiration timestamp of the bond (,i.e PT) correspond to which YT got minted.
    /// @param  amountOut Minimum No. of YTs, buyer is expecting to have after the trade.
    /// @param  recepient Destination at which newly minted YTs got transferred.
    /// @param  maxInput Maximum amount of shares buyer wants to spend on this trade.
    function purchaseYt(
        uint256 poolId,
        uint256 amountOut,
        address recepient,
        uint256 maxInput
    ) external {
        // No trade after expiration
        require(poolId > block.timestamp, "Todo nice time error");
        // Validate that `amount` is non zero.
        require(amountOut != uint256(0), "nice todo errors");
        // Read the cached reserves for the unlocked YT and bonds ,i.e. PT.
        uint128 cSharesReserve = reserves[poolId].shares;
        uint128 cBondsReserve = reserves[poolId].bonds;
        // Should check for the support with the pool.
        require(
            cSharesReserve != uint128(0) && cBondsReserve != uint128(0),
            "todo nice error"
        );
        // Calculate the shares received when selling `amountOut` PTs.
        uint256 sharesReceived = _sellBondsPreview(
            amountOut.toUFixedPoint(),
            uint256(cSharesReserve).toUFixedPoint(),
            uint256(cBondsReserve).toUFixedPoint()
        );
        // Calculate the shares without fee.
        uint256 sharesWithOutFee = _chargeFee(
            poolId,
            amountOut,
            sharesReceived,
            TradeType.SELL_PT
        );
        uint256 unlockedSharePrice = term.unlockedSharePrice();
        // Convert the shares into underlying. --- change them into appropriate decimals or use fixed point.
        uint256 underlyingAmt = (unlockedSharePrice * sharesWithOutFee) / _one;
        // Convert into remaining shares.
        uint256 sharesNeeded = (unlockedSharePrice * _one) /
            (amountOut - underlyingAmt);
        // Make sure user wouldn't end up paying more.
        require(sharesNeeded <= maxInput, "todo nice errors");
        // Transfer the remaining underlying shares from the buyer.
        IMultiToken(address(term)).transferFrom(
            _UNLOCK_TERM_ID,
            msg.sender,
            address(this),
            sharesNeeded
        );
        // Buy the PTs and YTs
        uint256[] memory ids = new uint256[](1);
        ids[0] = _UNLOCK_TERM_ID;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = sharesWithOutFee + sharesNeeded;
        (uint256 pt, uint256 yt) = term.lock(
            ids,
            amounts,
            0,
            recepient,
            address(this),
            block.timestamp,
            poolId
        );
        // Make sure that the generated PTs are equal to
        require(pt == amountOut, "todo nice error");
        // Updated reserves.
        _update(
            poolId,
            cBondsReserve + amountOut.toUint128(),
            cSharesReserve - sharesWithOutFee.toUint128()
        );
        emit YtPurchased(poolId, recepient, yt, sharesNeeded);
    }

    // TODO: Make sure the decimal precision is correct.
    /// @dev Facilitate the purchase of the bonds.
    /// @param  poolId Pool Id supported for the trade.
    /// @param  amount Amount of underlying asset (or base asset) provided to purchase the bonds.
    /// @param  cachedReserve Cached reserve at the time of trade.
    /// @return bondsAmountWithOutFee Amount of bond tokens, trade offers.
    /// @return changeInShares Change in shares reserve.
    /// @return changeInBonds  Change in bonds reserve.
    function _buyBonds(
        uint256 poolId,
        uint256 amount,
        Reserve memory cachedReserve
    )
        internal
        returns (
            uint256 bondsAmountWithOutFee,
            uint256 changeInShares,
            uint256 changeInBonds
        )
    {
        // Transfer the funds to the contract
        token.transferFrom(msg.sender, address(this), amount);

        // We deposit into the unlocked position of the term in order to calculate
        // the price per share and therefore implied interest rate.
        uint256[] memory empty = new uint256[](0);
        // Deposit the underlying token in to the tokenized vault
        // to get the shares of it.
        (, changeInShares) = term.lock(
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
        // buy bonds preview. changeInBonds ~ expectedBondsOut in terminology here
        changeInBonds = uint256(
            _buyBondsPreview(
                changeInShares.toUFixedPoint(),
                uint256(cachedReserve.shares).toUFixedPoint(),
                uint256(cachedReserve.bonds).toUFixedPoint()
            )
        );
        // Charge fee on the interest rate offered during the trade.
        bondsAmountWithOutFee = _chargeFee(
            poolId,
            changeInBonds,
            changeInShares,
            TradeType.BUY_PT
        );
    }

    // TODO: Make sure the decimal precision is correct.
    /// @dev Facilitate the sell of bond tokens.
    /// It will transfer the underlying token instead of the shares ??
    /// @param  poolId Pool Id supported for the trade.
    /// @param  amount Amount of bonds tokens user wants to sell in given trade.
    /// @param  cachedReserve Cached reserve at the time of trade.
    /// @param  receiver Address which would receive the underlying token.
    /// @return sharesWithOutFee Amount of shares, trade offers.
    /// @return changeInShares Change in shares reserve.
    /// @return changeInBonds  Change in bonds reserve.
    function _sellBonds(
        uint256 poolId,
        uint256 amount,
        Reserve memory cachedReserve,
        address receiver
    )
        internal
        returns (
            uint256 sharesWithOutFee,
            uint256 changeInShares,
            uint256 changeInBonds
        )
    {
        changeInBonds = amount;
        // Transfer the bonds to the contract
        IMultiToken(address(term)).transferFrom(
            poolId,
            msg.sender,
            address(this),
            amount
        );
        // Sell bonds preview. changeInShares ~ expectedSharesOut in terminology here
        uint256 changeInShares = _sellBondsPreview(
            amount.toUFixedPoint(),
            uint256(cachedReserve.shares).toUFixedPoint(),
            uint256(cachedReserve.bonds).toUFixedPoint()
        );
        // Charge fee on the interest rate offered during the trade.
        sharesWithOutFee = _chargeFee(
            poolId,
            changeInShares,
            amount,
            TradeType.SELL_PT
        );
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
    /// @param  newBondBalance current holdings of the bond tokens,i.e. PTs of the contract.
    /// @param  newSharesBalance current holding of the shares tokens by the contract.
    function _update(
        uint256 poolId,
        uint128 newBondBalance,
        uint128 newSharesBalance
    ) internal {
        // Update the reserves.
        reserves[poolId].bonds = newBondBalance;
        reserves[poolId].shares = newSharesBalance;
        emit Sync(poolId, newBondBalance, newSharesBalance);
    }

    /// @dev Charge fee for the trade.
    /// @param poolId Sub pool Id, Corresponds to it fees get updated.
    function _chargeFee(
        uint256 poolId,
        uint256 amountOut,
        uint256 amountIn,
        TradeType _type
    ) internal returns (uint256) {
        if (_type == TradeType.BUY_PT) {
            uint256 impliedFee = tradeFee
                .toUFixedPoint()
                .mulDown((amountOut - amountIn).toUFixedPoint())
                .fromUFixedPoint();
            fees[poolId].feesInBonds += impliedFee.toUint128();
            return amountOut - impliedFee;
        } else if (_type == TradeType.SELL_PT) {
            uint256 impliedFee = tradeFee
                .toUFixedPoint()
                .mulDown((amountIn - amountOut).toUFixedPoint())
                .fromUFixedPoint();
            fees[poolId].feesInShares += impliedFee.toUint128();
            return amountOut - impliedFee;
        }
    }

    /// @notice Update the `tradeFee` by the governance contract.
    function updateTradeFee(uint256 newTradeFee) external onlyGovernance {
        // Emit an event showing update
        emit TradeFeeUpdated(tradeFee, newTradeFee);
        // change the state
        tradeFee = newTradeFee;
    }

    function _normalize(uint256 input) internal returns (uint256) {
        if (_decimals < 18) {
            unchecked {
                uint256 adjustFactor = 10**(18 - _decimals);
                return input * adjustFactor;
            }
        } else {
            return input;
        }
    }

    function _denormalize(uint256 input) internal returns (uint256) {
        if (_decimals < 18) {
            unchecked {
                uint256 adjustFactor = 10**(18 - _decimals);
                return input / adjustFactor;
            }
        } else {
            return input;
        }
    }

    function _buyBondsPreview(
        UFixedPoint sharesIn,
        UFixedPoint sharesReserve,
        UFixedPoint bondsReserve
    ) internal view returns (uint128 _expectedBondOut) {
        // TODO - Access the library to know the amount.
    }

    function _sellBondsPreview(
        UFixedPoint bondsIn,
        UFixedPoint sharesReserve,
        UFixedPoint bondsReserve
    ) internal view returns (uint128 _expectedSharesOut) {
        // TODO - Access the library to know the amount.
    }
}
