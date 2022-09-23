// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./Pool.sol";
import "./Term.sol";
import "./libraries/Authorizable.sol";
import "./libraries/Errors.sol";

contract ElementRegistry is Authorizable {
    struct TermInfo {
        address term; // term contract address
        address pool; // pool contract address
    }

    event TermRegistered(address term, address pool);

    TermInfo[] private _terms;

    constructor(address owner) {
        setOwner(owner);
    }

    /// @notice Registers a new Term <> Pool combination
    /// @param term Term contract
    /// @param pool Associated Pool contract
    function register(Term term, Pool pool) public onlyAuthorized {
        // configuration check
        if (address(pool.term()) != address(term)) {
            revert ElementError.ElementRegistry_DifferentTermAddresses();
        }

        TermInfo memory info = TermInfo(address(term), address(pool));

        // add term info to registry list
        _terms.push(info);

        // Emit event for off-chain discoverability
        emit TermRegistered(address(term), address(pool));
    }

    /// @notice Helper function for fetching length of registry list
    function getRegistryCount() public view returns (uint256) {
        return _terms.length;
    }

    /// @notice Helper function for element of registry list
    /// @param index of the term list
    function getTermInfo(uint256 index) public view returns (TermInfo memory) {
        return _terms[index];
    }
}
