// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC4626Term } from "contracts/ERC4626Term.sol";

// Simple library helper fn for making tests cleaner
library Utils {
    // TODO Refactor to generalized function when interfaces for variant terms become standardized
    function underlyingAsUnlockedShares(ERC4626Term term, uint256 underlying)
        public
        returns (uint256)
    {
        (, , , uint256 impliedUnderlyingReserve) = term.reserveDetails();

        return
            impliedUnderlyingReserve == 0
                ? underlying
                : ((underlying * term.totalSupply(term.UNLOCKED_YT_ID())) /
                    impliedUnderlyingReserve);
    }
}
