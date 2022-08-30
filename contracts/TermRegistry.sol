// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./Pool.sol";
import "./Term.sol";
import "./libraries/Authorizable.sol";
import "./libraries/FixedPointMath.sol";

// Registry and Factory contract to store and create terms
contract TermRegistry is Authorizable {
    using FixedPointMath for uint256;

    struct TermInfo {
        // sstore
        address termAddress; // term contract address
        address poolAddress; // pool contract address
        uint24 yieldSourceId; // arbitrary identifier, e.g. 1 = Yearn, 2 = Compound
        // sstore
        uint256 expiry; // term and pool multi-token identifier
    }

    event TermRegistered(
        address indexed term,
        address indexed pool,
        uint24 indexed yieldSourceId,
        bytes32 id,
        uint256 expiry
    );

    mapping(bytes32 => TermInfo) private _termData;
    bytes32[] public terms;

    constructor(address governance) {
        setOwner(governance); // set owner to governance
    }

    /// @notice Adds a new or existing term to the registry
    /// @param term Term contract
    /// @param pool Associated pool contract
    /// @param expiry The expiry of the term and multi-token identifier
    /// @param yieldSourceId Arbitrary identifier, e.g. 1 = Yearn, 2 = Compound, etc.
    /// @return id Keccak-256 hash identifier of the newly registered term
    function registerTerm(
        Term term,
        Pool pool,
        uint256 expiry,
        uint24 yieldSourceId
    ) public onlyAuthorized returns (bytes32) {
        address termAddress = address(term);
        address poolAddress = address(pool);
        // Create hash from (termAddress, poolAddress, expiry)
        bytes32 termId = keccak256(
            abi.encodePacked(termAddress, poolAddress, expiry)
        );

        TermInfo memory info = TermInfo(
            termAddress,
            poolAddress,
            yieldSourceId,
            expiry
        );

        // add term info to mapping data mapping
        _termData[termId] = info;
        // push term id to terms array
        terms.push(termId);

        emit TermRegistered(
            termAddress,
            poolAddress,
            yieldSourceId,
            termId,
            expiry
        );

        return (termId);
    }

    struct PoolConfig {
        uint32 timestretch; // timestretch for pool
        uint16 maxTime; // orcale params
        uint16 maxLength; // orcale params
        uint256 outputAmount; // expected underlying seeder receives back, might remove this
    }

    /// @notice Creates a new term and adds it to this registry
    /// @param term Term contract
    /// @param pool Associated pool contract
    /// @param poolConfig sub-pool configuration
    /// @param expiry The expiry of the term and multi-token identifier
    /// @param yieldSourceId Arbitrary identifier, e.g. 1 = Yearn, 2 = Compound
    /// @param seeder The address seeding new term with underlying funds
    /// @param lockedAmount Amount of underlying tokens to mint PTs and YTs (lock)
    /// @param unlockedAmount Amount of underlying tokens to deposit into the AMM unlocked
    /// @param ptAmount Amount of PTs to sell into the AMM to set target APY
    /// @param outputAmount Amount of underlying tokens the seeder should receive after initializing the sub-pool
    function createTerm(
        Term term,
        Pool pool,
        PoolConfig memory poolConfig,
        uint256 expiry,
        uint24 yieldSourceId,
        address seeder,
        uint256 lockedAmount,
        uint256 unlockedAmount,
        uint256 ptAmount,
        uint256 outputAmount
    ) public {
        // safety check to ensure both term and pool have the same forwarder factory
        require(pool.factory == term.factory, "different factories");

        // transfer the underlying token to this contract
        // seeder must have given this contract allowance
        term.token().transferFrom(seeder, address(this), lockedAmount);

        // beautiful type inferencing skills of solidity
        uint256[] memory emptyArray;

        // create a new sub-term with given expiry
        // YTs are sent to the seeder, PTs kept for pool initializatoin trade
        // only supports creating a term with underlying tokens not PTs/YTs
        term.lock(
            emptyArray,
            emptyArray,
            lockedAmount, // amount of underlying tokens to lock
            false, // no prefunding
            seeder, // YT destination
            address(this), // PT destination
            block.timestamp, // YT start time
            expiry
        );

        // creates a sub-pool with the given expiry and configuration
        pool.registerPoolId(
            expiry,
            unlockedAmount, // amount of underlying tokens to be deposited in AMM as unlocked
            poolConfig.timestretch,
            seeder, // LP token destination
            poolConfig.maxTime,
            poolConfig.maxLength
        );

        // sell PTs into the pool to initialize the pool with a target APY
        pool.tradeBonds(
            expiry,
            ptAmount, // amount of PTs to sell into the pool
            poolConfig.outputAmount, // min amount of underlying tokens seeder should recieve
            seeder, // resulting underlying is accredited to seeder
            false // selling PTs
        );

        // register term
        registerTerm(term, pool, expiry, yieldSourceId);
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

    /// @notice Gets all registered terms stored in this contract, including expired terms.
    ///         Useful for getting full term information off-chain
    /// @return array of all registered terms, including expired terms
    function getAllTerms() external view returns (TermInfo[] memory) {
        TermInfo[] memory allTerms = new TermInfo[](terms.length);

        for (uint256 i = 0; i < terms.length; i++) {
            TermInfo memory term = _termData[terms[i]];
            allTerms[i] = term;
        }

        return allTerms;
    }

    /// @notice Gets all active terms stored in this contract, excluding expired terms.
    ///         Useful for getting active term information off-chain.
    /// @return array of all active terms, excluding expired terms.
    function getAllActiveTerms() external view returns (TermInfo[] memory) {
        TermInfo[] memory allActiveTerms = new TermInfo[](terms.length);

        for (uint256 i = 0; i < terms.length; i++) {
            TermInfo memory term = _termData[terms[i]];
            if (block.timestamp < term.expiry) {
                allActiveTerms[i] = term;
            }
        }

        return allActiveTerms;
    }
}
