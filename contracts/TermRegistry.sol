// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./Pool.sol";
import "./Term.sol";
import "./ElementRegistry.sol";
import "./libraries/Authorizable.sol";
import "./libraries/FixedPointMath.sol";

contract TermRegistry is Authorizable {
    ElementRegistry public immutable registry;

    struct Expiry {
        uint256 start;
        uint256 end;
    }

    struct PoolConfig {
        uint32 timeStretch; // time stretch for pool
        uint16 maxTime; // oracle params
        uint16 maxLength; // oracle params
    }

    event ExpiryRegistered(
        uint256 start,
        uint256 end,
        uint256 indexed termIndex
    );

    // Integrations index in the ElementRegistry to list of expiries
    mapping(uint256 => Expiry[]) private _expiries;

    constructor(address owner, ElementRegistry _registry) {
        setOwner(owner);
        registry = _registry;
    }

    /// @notice Adds a new expiry to the registry
    /// @param index Index of the integration information in the integrations list.
    /// @param start Term start timestamp.
    /// @param end Term end timestamp.
    function register(
        uint256 index,
        uint256 start,
        uint256 end
    ) public onlyAuthorized {
        Expiry memory expiry = Expiry(start, end);
        // add expiry to list
        _expiries[index].push(expiry);
        // Emit event for off-chain discoverability
        emit ExpiryRegistered(start, end, index);
    }

    /// @notice Creates a new term from an approved Term list.
    /// @param index index of the term information in the term list.
    /// @param poolConfig sub-pool configuration.
    /// @param expiry The expiry of the term and multi-token identifier.
    /// @param lockedAmount Amount of underlying tokens to mint PTs and YTs (lock).
    /// @param unlockedAmount Amount of underlying tokens to deposit into the AMM unlocked.
    /// @param ptAmount Amount of PTs to sell into the AMM to set target APY.
    /// @param outputAmount Min amount of underlying tokens the seeder should recieve in the trade.
    /// @return timestamp tuple representing the start and end time for the new term.
    function createTerm(
        uint256 index,
        PoolConfig memory poolConfig,
        uint256 expiry,
        uint256 lockedAmount,
        uint256 unlockedAmount,
        uint256 ptAmount,
        uint256 outputAmount
    ) public onlyAuthorized returns (uint256, uint256) {
        ElementRegistry.Integration memory termInfo = registry.getIntegration(
            index
        );
        Term term = Term(termInfo.term);
        Pool pool = Pool(termInfo.pool);

        // cache token holdings
        // uint256 underlyingTotal = term.token().balanceOf(address(this));
        // uint256 ptTotal = term.balanceOf(expiry, address(this));

        // transfer token from seeder to this contract
        // seeder must have given proper approval before call
        // if (seeder != address(this)) {
        //     term.token().transferFrom(
        //         seeder,
        //         address(this),
        //         lockedAmount + unlockedAmount
        //     );
        // }

        uint256[] memory emptyArray;

        // creates a new term with given expiry
        // YTs are sent to seeder, PTs kept for pool initialization trade
        // only supports creating term with underlying tokens not expired PTs/YTs
        term.lock(
            emptyArray, // no expired PTs will be used to initialize term
            emptyArray, // no expired PTs will be used to initialize term
            lockedAmount, // amount of underlying tokens to lock
            false, // no pre-funding
            address(this), // YT destination
            address(this), // PT destination
            block.timestamp, // YT start time
            expiry
        );

        // creates a pool with given expiry and configuration
        pool.registerPoolId(
            expiry,
            unlockedAmount, // amount of underlying tokens to be deposited in AMM as unlocked
            poolConfig.timeStretch,
            address(this), // LP token destination
            poolConfig.maxTime,
            poolConfig.maxLength
        );

        // sell PTs into the pool to initialize with a target APY
        pool.tradeBonds(
            expiry,
            ptAmount, // amount of PTs to sell into the pool
            outputAmount, // min amount of underlying tokens seeder should recieve
            address(this), // resulting underlying is accredited to seeder
            false // selling PTs
        );

        // return excess capital to seeder
        // if (seeder != address(this)) {
        //     uint256 currentUnderlyingTotal = term.token().balanceOf(
        //         address(this)
        //     );
        //     term.token().transferFrom(
        //         address(this),
        //         seeder,
        //         currentUnderlyingTotal - underlyingTotal
        //     );

        //     uint256 currentPtTotal = term.balanceOf(expiry, address(this));
        //     term.transferFrom(
        //         expiry,
        //         address(this),
        //         seeder,
        //         currentPtTotal - ptTotal
        //     );
        // }

        register(index, block.timestamp, expiry);

        return (block.timestamp, expiry);
    }

    /// @notice Helper function to get length of registered expiries array from a valid Term
    /// @param index a
    function getExpiriesCount(uint256 index) public view returns (uint256) {
        return _expiries[index].length;
    }

    /// @notice Helper to get list of registered expiries from a valid Term
    /// @param index a
    function getExpiries(uint256 index) public view returns (Expiry[] memory) {
        return _expiries[index];
    }
}
