// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./Pool.sol";
import "./Term.sol";
import "./libraries/Authorizable.sol";

// Registry and Factory contract to store and create terms
contract TermRegistry is Authorizable {
    struct TermInfo {
        address termAddress; // term contract address
        address poolAddress; // pool contract address
        uint24 yieldSourceId; // arbitrary identifier, e.g. 1 = Yearn, 2 = Compound
    }

    event TermRegistered(
        address term,
        address pool,
        uint24 indexed yieldSourceId
    );

    TermInfo[] private _terms;

    constructor(address owner) {
        setOwner(owner);
    }

    /// @notice Adds a new or existing Term to the registry
    /// @param term Term contract
    /// @param pool Associated pool contract
    /// @param yieldSourceId Arbitrary identifier, e.g. 1 = Yearn, 2 = Compound, etc.
    function registerTerm(
        Term term,
        Pool pool,
        uint24 yieldSourceId
    ) public onlyAuthorized {
        // cache addresses
        address termAddress = address(term);
        address poolAddress = address(pool);

        // configuration check
        require(
            address(pool.term()) == termAddress,
            "pool's term address != term address"
        );

        TermInfo memory info = TermInfo(
            termAddress,
            poolAddress,
            yieldSourceId
        );

        // add term info to term array
        _terms.push(info);

        // Emit event for filtering by yield source id
        emit TermRegistered(termAddress, poolAddress, yieldSourceId);
    }

    function getTermsCount() public view returns (uint256) {
        return _terms.length;
    }

    function getTerm(uint256 index) public view returns (TermInfo memory) {
        return _terms[index];
    }
}
