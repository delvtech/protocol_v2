// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./Pool.sol";
import "./Term.sol";
import "./TermRegistry.sol";
import "./libraries/Authorizable.sol";
import "./libraries/FixedPointMath.sol";
import "forge-std/console.sol";

// An extension to the TermRegistry that supports blessing particular timestamps
contract ExpiryRegistry is Authorizable {
    using FixedPointMath for uint256;

    TermRegistry public immutable registry;

    struct Expiry {
        uint256 start;
        uint256 end;
    }

    struct PoolConfig {
        uint32 timestretch; // timestretch for pool
        uint16 maxTime; // orcale params
        uint16 maxLength; // orcale params
        uint256 outputAmount; // expected underlying seeder receives back, might remove this
    }

    // termId in the TermRegistry to list of expiries
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
        _expiries[termIndex].push(e);
    }

    /// @notice Creates a new sub-term from an approved Term list
    /// @param termIndex index of the term information in the term list
    /// @param poolConfig sub-pool configuration
    /// @param expiry The expiry of the term and multi-token identifier
    /// @param seeder The address seeding new term with underlying funds
    /// @param lockedAmount Amount of underlying tokens to mint PTs and YTs (lock)
    /// @param unlockedAmount Amount of underlying tokens to deposit into the AMM unlocked
    /// @param ptAmount Amount of PTs to sell into the AMM to set target APY.
    ///             Use the "calculatePTsNeededForTargetAPY" helper function off-chain for ideal amount
    function createTerm(
        uint256 termIndex,
        PoolConfig memory poolConfig,
        uint256 expiry,
        address seeder,
        uint256 lockedAmount,
        uint256 unlockedAmount,
        uint256 ptAmount
    ) public onlyAuthorized returns (uint256, uint256) {
        // check for valid term index
        // TermRegistry.TermInfo[] storage terms = registry.terms;
        // require(
        //     termIndex < terms.length && termIndex >= 0,
        //     "invalid term index"
        // );

        // fetch term information by term index
        // term index can be resolved off-chain
        TermRegistry.TermInfo memory termInfo = registry.getTerm(termIndex);
        Term term = Term(termInfo.termAddress);
        Pool pool = Pool(termInfo.poolAddress);

        // cache token holdings
        uint256 underlyingTotal = term.token().balanceOf(address(this));
        uint256 ptTotal = term.balanceOf(expiry, address(this));

        // transfer token from seeder to this contract
        // seeder must have given proper allowance before call
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

        console.logUint(term.balanceOf(expiry, seeder));

        // sell PTs into the pool to initialize with a target APY
        pool.tradeBonds(
            expiry,
            ptAmount, // amount of PTs to sell into the pool
            poolConfig.outputAmount, // min amount of underlying tokens seeder should recieve
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

    /// @dev formula source (https://paper.element.fi/#e-initializing-the-convergent-curve-pool-price)
    /// @notice Creates a new term and adds it to this registry
    /// @param pool Associated pool contract
    /// @param expiry The expiry of the term and multi-token identifier
    /// @param targetAPY APY pool should be initialized to, 18 point fixed point number
    function calculatePTsNeededForTargetAPY(
        Pool pool,
        uint256 expiry,
        uint256 targetAPY
    ) external view returns (uint256) {
        (uint32 timestretch, ) = pool.parameters(expiry);
        uint256 timeRemaining = expiry - block.timestamp;
        uint256 _one = 1e18;

        uint256 poolSupply = pool.totalSupply(expiry);
        uint256 a = _one.sub(targetAPY.mulDivDown(timeRemaining, 100e18));
        uint256 aPowExp = uint256(timestretch).divDown(timeRemaining);
        uint256 aPow = (_one.divDown(a)).pow(aPowExp);
        uint256 num = poolSupply.mulDown(aPow.sub(1));
        uint256 den = _one.add(aPow);
        return num.divDown(den);
    }

    function getExpiriesCount(uint256 termIndex) public view returns (uint256) {
        return _expiries[termIndex].length;
    }

    function getExpiries(uint256 termIndex)
        public
        view
        returns (Expiry[] memory)
    {
        return _expiries[termIndex];
    }
}
