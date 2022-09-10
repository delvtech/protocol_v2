// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { ERC4626Term } from "contracts/ERC4626Term.sol";

contract ElementTest is Test {
    uint256 public constant YEAR = (365 * 24 * 60 * 60);

    function mkAddr(string memory name) internal returns (address addr) {
        addr = vm.addr(uint256(keccak256(abi.encodePacked(name))));
        vm.deal(addr, 100 ether);
        vm.label(addr, name);
    }
}

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

    // FIXME: Document and/or test this
    function generateTestingMatrix(uint256 rows, uint256[] memory inputs)
        internal
        pure
        returns (uint256[][] memory result)
    {
        result = new uint256[][](inputs.length**rows);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = new uint256[](rows);
            for (uint256 j = 0; j < rows; j++) {
                result[i][j] = inputs[
                    (i / (result.length / (inputs.length**(j + 1)))) %
                        inputs.length
                ];
            }
        }
        return result;
    }
}
