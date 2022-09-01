// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./Pool.sol";
import "./Term.sol";
import "./TermRegistry.sol";
import "./libraries/Authorizable.sol";
import "./libraries/FixedPointMath.sol";

// An extension to the TermRegistry that supports blessing particular timestamps
contract ExpiryRegistry is Authorizable {
    TermRegistry public immutable registry;

    struct Expiry {
        uint256 start;
        uint256 end;
    }

    // termId in the TermRegistry to list of expiries
    mapping(uint256 => Expiry[]) public expiries;

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
        expiries[termIndex].push(e);
    }
}
