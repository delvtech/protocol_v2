// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import "./MultiToken.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ITerm.sol";
import "./libraries/FixedPoint.sol";
import "./libraries/LogExpMath.sol";

// LP is a multitoken [ie fake 1155] contract which accepts deposits and withdraws
// from the AMM.
contract LP is MultiToken {
    // Use the fixed point libraries on uin256s
    using FixedPoint for uint256;
    using LogExpMath for uint256;

    // The token standard indexes each token by an ID which for these LP
    // tokens will be the expiration time of the token which matures.
    // Deposits input the underlying asset and a proportion will be locked
    // till expiry to match the current ratio of the pool

    // Holds the reserve amounts in an gas friendly way
    struct Reserve {
        uint128 shares;
        uint128 bonds;
    }

    // Maps pool ID to the reserves for that term
    mapping(uint256 => Reserve) public reserves;
    // The term address cannot be changed after deploy.
    // All funds are held in the term contract.
    ITerm immutable term;
    // The underlying token on which yield is earned
    IERC20 immutable token;
    uint8 immutable decimals;
    // One expressed in the native token math
    uint256 immutable one;

    // The id for the unlocked deposit into the term
    uint256 constant unlockedTermID = 0;

    /// @notice Runs the initial deployment code
    /// @param _token The token which is deposited into this contract
    /// @param _term The term which locks and earns yield on token
    /// @param _linkerCodeHash The hash of the erc20 linker contract deploy code
    /// @param _factory The factory which is used to deploy the linking contracts
    constructor(
        IERC20 _token,
        ITerm _term,
        bytes32 _linkerCodeHash,
        address _factory
    ) MultiToken(_linkerCodeHash, _factory) {
        token = _token;
        uint8 _decimals = _token.decimals();
        decimals = _decimals;
        one = 10**_decimals;
        term = _term;
    }

    function depositUnderlying(
        uint256 amount,
        uint256 poolId,
        uint256 minOutput
    ) external returns (uint256) {
        // No minting after expiration
        require(poolId > block.timestamp, "Todo nice time error");
        // Transfer from the user
        token.transferFrom(msg.sender, address(this), amount);
        // We deposit into the unlocked position of the term in order to calculate
        // the price per share and therefore implied interest rate.
        // This is the step that deposits all value provided into the yield source
        // Note - we need a pointless storage to memory to convince the solidity type checker
        // to understand the type of []
        uint256[] memory empty = new uint256[](0);
        (uint256 depositedShares, ) = term.lock(
            empty,
            empty,
            amount,
            // there's no yt from this
            msg.sender,
            address(this),
            0,
            unlockedTermID
        );

        // Calculate the implicit price per share
        uint256 pricePerShare = (amount * one) / depositedShares;
        // Call internal function to mint new lp from the new shares held by this contract
        uint256 newLpToken = depositFromShares(
            poolId,
            uint256(reserves[poolId].shares),
            uint256(reserves[poolId].bonds),
            depositedShares,
            pricePerShare,
            msg.sender
        );
        // Check enough has been made and return that amount
        require(newLpToken >= minOutput, "Todo nice errors");
        return (newLpToken);
    }

    // Intentionally unfriendly, user says they have pts, also transfers in shares to ratio
    // should be used with weiroll
    function depositBonds(
        uint256 poolId,
        uint256 ptDeposited,
        address destination,
        uint256 minLpOut
    ) external returns (uint256) {
        // No minting after expiration
        require(poolId > block.timestamp, "Todo nice time error");
        // Load the pool details
        uint256 loadedShares = uint256(reserves[poolId].shares);
        uint256 loadedBonds = uint256(reserves[poolId].bonds);
        // Transfer the pt from the user
        term.transferFrom(poolId, msg.sender, address(this), ptDeposited);
        // Calculate ratio of the shares needed
        uint256 sharesNeeded = (loadedShares * ptDeposited) / loadedBonds;
        // Transfer shares from user
        term.transferFrom(
            unlockedTermID,
            msg.sender,
            address(this),
            sharesNeeded
        );
        // Calculate Lp
        uint256 lpCreated = (totalSupply[poolId] * ptDeposited) / loadedBonds;
        // Mint LP
        _mint(poolId, destination, lpCreated);
        // Update the reserve state
        reserves[poolId].shares = uint128(loadedShares + sharesNeeded);
        reserves[poolId].bonds = uint128(loadedBonds + ptDeposited);
        // Check enough has been made and return that amount
        require(lpCreated >= minLpOut, "Todo nice errors");
        return (lpCreated);
    }

    function withdraw(
        uint256 poolId,
        uint256 amount,
        address destination
    ) external {
        // Burn lp token and free assets. Will also finalize the pool and so return
        // zero for the userBonds if it's after expiry time.
        (uint256 userShares, uint256 userBonds) = withdrawToShares(
            poolId,
            amount,
            msg.sender
        );

        // We've turned the LP into constituent assets and so now we transfer them to the user
        // By withdrawing shares and then (optionally) transferring PT to them

        // Create the arrays for a withdraw from term
        uint256[] memory ids = new uint256[](1);
        ids[0] = poolId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = userShares;
        // Do the withdraw to user account
        term.unlock(destination, ids, amounts);

        // Now if there are also bonds [ie if the pool is not yet expired we transfer to the user]
        if (userBonds != 0) {
            // We transfer directly to them
            term.transferFrom(poolId, address(this), msg.sender, userBonds);
        }
    }

    function rollover(
        uint256 fromPoolId,
        uint256 toPoolId,
        uint256 amount,
        address destination,
        uint256 minOutput
    ) external returns (uint256) {
        // Only expired bonds can be rolled over
        require(
            fromPoolId < block.timestamp && toPoolId > block.timestamp,
            "Todo nice time error"
        );
        // Burn lp token and free assets. Will also finalize the pool and so return
        // zero for the userBonds if it's after expiry time.
        (uint256 userShares, ) = withdrawToShares(
            fromPoolId,
            amount,
            msg.sender
        );
        // In this case we have no price per share information so we must ask the pool for it
        uint256 pricePerShare = term.unlockedSharePrice();
        // Now the freed shares are deposited
        uint256 newLpToken = depositFromShares(
            toPoolId,
            uint256(reserves[toPoolId].shares),
            uint256(reserves[toPoolId].bonds),
            userShares,
            pricePerShare,
            destination
        );
        // Require that the output matches user expectations
        require(newLpToken >= minOutput, "Todo nice expectation error");
        return (newLpToken);
    }

    // Should be called after a user has yielding shares from the term and needs to put them into
    // a term, such as when they rollover or when they deposit single sided.
    function depositFromShares(
        uint256 poolId,
        uint256 currentShares,
        uint256 currentBonds,
        uint256 depositedShares,
        uint256 pricePerShare,
        address to
    ) internal returns (uint256) {
        // Must be initialized
        require(
            currentShares != 0 || currentBonds != 0,
            "todo nice initialization error"
        );
        // Calculate total reserve with conversion to underlying units
        // IE: amount_bonds + amountShares*underlyingPerShare
        uint256 totalValue = currentShares * pricePerShare + currentBonds;
        // Calculate the needed bonds as a percent of the value
        uint256 depositedAmount = (depositedShares * pricePerShare) / one;
        uint256 neededBonds = (depositedAmount * currentBonds) / totalValue;
        // The bond value is in terms of purely the underlying so to figure out how many shares we lock
        // we dived it by our price per share to convert to share value.
        uint256 sharesToLock = (neededBonds * one) / pricePerShare;
        // Shares to lock is in 18 point so we convert back and then lock shares to PTs
        // while sending the resulting YT to the user

        // Note need to declare dynamic memory types in this way even with one element
        uint256[] memory ids = new uint256[](1);
        ids[0] = unlockedTermID;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = sharesToLock;
        // then make the call
        term.lock(
            ids,
            amounts,
            0,
            to,
            address(this),
            block.timestamp,
            // Note Pools Ids come from their PT expiry time
            poolId
        );

        // Mint new LP in equal proportion to the increase in shares
        uint256 increaseInShares = depositedShares - sharesToLock;
        uint256 newLpToken = (totalSupply[poolId] * increaseInShares) /
            currentShares;
        _mint(poolId, to, newLpToken);
        // Now we have increased the amount of shares and we have increased the number of bonds an equal proportion
        // So we change their state in storage
        // todo non optimal state use
        reserves[poolId].shares += uint128(increaseInShares);
        reserves[poolId].bonds += uint128(neededBonds);
        // Return the LP produced
        return (newLpToken);
    }

    function withdrawToShares(
        uint256 poolId,
        uint256 amount,
        address source
    ) internal returns (uint256 userShares, uint256 userBonds) {
        // Load the reserves
        uint256 reserveBonds = uint256(reserves[poolId].bonds);
        uint256 reserveShares = uint256(reserves[poolId].shares);

        // Two different cases, either the pool is expired and the user can get out the underlying
        // or the pool is not expired and the user can withdraw only bonds and underlying
        // So if the pool is expired and has not withdrawn then we must withdraw
        // Leverage that the poolId == expiration
        if (block.timestamp >= poolId && reserveBonds != 0) {
            // In this misnomer case we 'lock' the bonds from their PT state
            // to a unlocked token, which matches the rest of the reserves.
            // This ensures that the LP earns interest post expiry even if not withdrawing
            uint256[] memory ids = new uint256[](1);
            ids[0] = poolId;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = uint256(reserveBonds);
            (uint256 sharesDeposited, ) = term.lock(
                ids,
                amounts,
                0,
                // there's no yt from this
                address(this),
                address(this),
                0,
                unlockedTermID
            );
            // Now we update the cached reserves
            reserveBonds = 0;
            reserveShares += sharesDeposited;
        }

        // Cache the total supply for withdraws
        uint256 cachedTotalSupply = totalSupply[poolId];
        // We burn here prevent some edge case chance of reentrancy
        _burn(poolId, source, amount);

        // Calculate share percent
        userShares = (amount * reserveShares) / cachedTotalSupply;
        // Update the cached reserves
        reserveShares -= userShares;

        // The user gets out a pure percent of the total supply
        userBonds = (amount * reserveBonds) / cachedTotalSupply;
        // Update the cached reserves
        reserveBonds -= userBonds;

        // Finally we update the state about this pool
        reserves[poolId].bonds = uint128(reserveBonds);
        reserves[poolId].shares = uint128(reserveShares);
    }
}
