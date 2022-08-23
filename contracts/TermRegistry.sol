// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./libraries/Authorizable.sol";
import "./Term.sol";
import "./Pool.sol";

// Registry contract to store and retrieve term data
contract TermRegistry is Authorizable {
    struct TermInfo {
        // sstore
        address termAddress; // address of the term contract
        address poolAddress; // address of the pool contract,
        uint24 yieldSourceId; // arbitrary identifier, e.g. 1 = Yearn, 2 = Compound, etc.
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

    address public immutable factory; // ERC20 forwarder factory registered in term and pool contracts
    mapping(bytes32 => TermInfo) private _termData;
    bytes32[] public terms;

    constructor(address governance, address _factory) {
        setOwner(governance); // set authorizable owner to governance
        factory = _factory;
    }

    /// @notice Add a term to a registery
    /// @param term Term contract
    /// @param pool Associated pool contract
    /// @param expiry The expiry of the term and multi-token identifier
    /// @param yieldSourceId Arbitrary identifier, e.g. 1 = Yearn, 2 = Compound, etc.
    /// @return id Keccak-256 hash identifier of the registered term
    function registerTerm(
        Term term,
        Pool pool,
        uint256 expiry,
        uint24 yieldSourceId
    ) public onlyAuthorized returns (bytes32) {
        require(expiry > block.timestamp, "expired term");

        address termAddress = address(term);
        address poolAddress = address(pool);

        // create id from (termAddress, poolAddress, expiry) hash
        bytes32 id = keccak256(
            abi.encodePacked(termAddress, poolAddress, expiry)
        );

        TermInfo memory info = TermInfo(
            termAddress,
            poolAddress,
            yieldSourceId,
            expiry
        );

        // add term info to mapping with id as key
        _termData[id] = info;

        // push id to terms array
        terms.push(id);

        emit TermRegistered(
            termAddress,
            poolAddress,
            yieldSourceId,
            id,
            expiry
        );

        return (id);
    }

    /// @notice Gets all terms registered by this contract, including expired terms.
    ///         Useful for getting term information off-chain
    /// @return All terms registered by this contract, including expired terms
    function getAllTerms() public view returns (TermInfo[] memory) {
        TermInfo[] memory allTerms = new TermInfo[](terms.length);

        for (uint256 i = 0; i < terms.length; i++) {
            TermInfo memory term = _termData[terms[i]];
            allTerms[i] = term;
        }

        return allTerms;
    }

    /// @notice Gets all active terms registered by this contract, excluding expired terms.
    ///         Useful for getting active term information off-chain
    /// @return All active terms registered by this contract, excluding expired terms.
    function getAllActiveTerms() public view returns (TermInfo[] memory) {
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
