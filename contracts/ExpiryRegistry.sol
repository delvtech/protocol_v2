// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./Pool.sol";
import "./Term.sol";
import "./TermRegistry.sol";
import "./libraries/Authorizable.sol";
import "./libraries/FixedPointMath.sol";

// Expiry Registry for Element V2 Protocol
// Extends a Term Registry contract by adding support for registering particular expiries
contract ExpiryRegistry is Authorizable {
    TermRegistry public immutable registry;

    struct Expiry {
        uint256 start;
        uint256 end;
    }

    struct PoolConfig {
        uint32 timestretch; // timestretch for pool
        uint16 maxTime; // orcale params
        uint16 maxLength; // orcale params
    }

    event ExpiryRegistered(
        uint256 start,
        uint256 end,
        uint256 indexed termIndex
    );

    // termIndex in the TermRegistry to list of expiries
    mapping(uint256 => Expiry[]) private _expiries;

    constructor(address owner, TermRegistry _registry) {
        setOwner(owner);
        registry = _registry;
    }

    function registerExpiry(
        uint256 termIndex,
        uint256 start,
        uint256 expiry
    ) public onlyAuthorized {
        Expiry memory e = Expiry(start, expiry);
        // add expiry to list
        _expiries[termIndex].push(e);

        // Emit event for off-chain discoverability
        emit ExpiryRegistered(start, expiry, termIndex);
    }

    /// @notice Creates a new term from an approved Term list.
    /// @param termIndex index of the term information in the term list.
    /// @param poolConfig sub-pool configuration.
    /// @param expiry The expiry of the term and multi-token identifier.
    /// @param seeder The address seeding new term with underlying funds.
    /// @param lockedAmount Amount of underlying tokens to mint PTs and YTs (lock).
    /// @param unlockedAmount Amount of underlying tokens to deposit into the AMM unlocked.
    /// @param ptAmount Amount of PTs to sell into the AMM to set target APY.
    /// @param outputAmount Min amount of underlying tokens the seeder should recieve in the trade.
    function createTerm(
        uint256 termIndex,
        PoolConfig memory poolConfig,
        uint256 expiry,
        address seeder,
        uint256 lockedAmount,
        uint256 unlockedAmount,
        uint256 ptAmount,
        uint256 outputAmount
    ) public onlyAuthorized returns (uint256, uint256) {
        TermRegistry.TermInfo memory termInfo = registry.getTermInfo(termIndex);
        Term term = Term(termInfo.termAddress);
        Pool pool = Pool(termInfo.poolAddress);

        // cache token holdings
        uint256 underlyingTotal = term.token().balanceOf(address(this));
        uint256 ptTotal = term.balanceOf(expiry, address(this));

        // transfer token from seeder to this contract
        // seeder must have given proper approval before call
        if (seeder != address(this)) {
            term.token().transferFrom(
                seeder,
                address(this),
                lockedAmount + unlockedAmount
            );
        }

        // beautiful type inferencing of solidity
        uint256[] memory emptyArray;

        // creates a new term with given expiry
        // YTs are sent to seeder, PTs kept for pool initializatoin trade
        // only supports creating term with underlying tokens not expired PTs/YTs
        term.lock(
            emptyArray, // no expired PTs will be used to initialize term
            emptyArray, // no expired PTs will be used to initialize term
            lockedAmount, // amount of underlying tokens to lock
            false, // no prefunding
            seeder, // YT destination
            address(this), // PT destination
            block.timestamp, // YT start time
            expiry
        );

        // creates a pool with given expiry and configuration
        pool.registerPoolId(
            expiry,
            unlockedAmount, // amount of underlying tokens to be deposited in AMM as unlocked
            poolConfig.timestretch,
            seeder, // LP token destination
            poolConfig.maxTime,
            poolConfig.maxLength
        );

        // sell PTs into the pool to initialize with a target APY
        pool.tradeBonds(
            expiry,
            ptAmount, // amount of PTs to sell into the pool
            outputAmount, // min amount of underlying tokens seeder should recieve
            seeder, // resulting underlying is accredited to seeder
            false // selling PTs
        );

        // return excess capital to seeder
        if (seeder != address(this)) {
            uint256 currentUnderlyingTotal = term.token().balanceOf(
                address(this)
            );
            term.token().transferFrom(
                address(this),
                seeder,
                currentUnderlyingTotal - underlyingTotal
            );

            uint256 currentPtTotal = term.balanceOf(expiry, address(this));
            term.transferFrom(
                expiry,
                address(this),
                seeder,
                currentPtTotal - ptTotal
            );
        }

        registerExpiry(termIndex, block.timestamp, expiry);

        return (block.timestamp, expiry);
    }

    /// @notice Helper function to get length of registered expiries array from a valid Term
    /// @param termIndex index of the term in the term registry
    function getExpiriesCount(uint256 termIndex) public view returns (uint256) {
        return _expiries[termIndex].length;
    }

    /// @notice Helper to get list of registered expiries from a valid Term
    /// @param termIndex index of the term in the term registry
    function getExpiries(uint256 termIndex)
        public
        view
        returns (Expiry[] memory)
    {
        return _expiries[termIndex];
    }
}
