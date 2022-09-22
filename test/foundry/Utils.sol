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
    function encodeAssetId(
        bool isYieldToken,
        uint256 startDate,
        uint256 expirationDate
    ) internal pure returns (uint256) {
        return
            (uint256(isYieldToken ? 1 : 0) << 255) |
            (startDate << 128) |
            expirationDate;
    }

    // @notice Generates a matrix of all of the different combinations of
    //         inputs for each row.
    // @dev In order to generate the full testing matrix, we need to generate
    //      cases for each value that use all of the input values. In order
    //      to do this, we segment the set of test cases into subsets for each
    //      entry
    // @param inputs A matrix of uint256 values that defines the inputs that
    //        will be used to generate combinations for each row. Increasing the
    //        number of inputs dramatically increases the amount of test cases
    //        that will be generated, so it's important to limit the amount of
    //        inputs to a small number of meaningful values. We use uint256 for
    //        generality, since uint256 can be converted to small width types.
    // @return The full testing matrix.
    function generateTestingMatrix(uint256[][] memory inputs)
        internal
        pure
        returns (uint256[][] memory result)
    {
        // Compute the divisors that will be used to compute the intervals for
        // every input row.
        uint256 base = 1;
        uint256[] memory intervalDivisors = new uint256[](inputs.length);
        for (uint256 i = 0; i < inputs.length; i++) {
            base *= inputs[i].length;
            intervalDivisors[i] = base;
        }
        // Generate the testing matrix.
        result = new uint256[][](base);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = new uint256[](inputs.length);
            for (uint256 j = 0; j < inputs.length; j++) {
                // The idea behind this calculation is that we split the set of
                // test cases into sections and assign one input value to each
                // section. For the first row, we'll create {inputs[0].length}
                // sections and assign these values to sections linearly. For
                // row 1, we'll create inputs[0].length * inputs[1].length
                // sections, and we'll assign the 0th input to the first
                // section, the 1st input to the second section, and continue
                // this process (wrapping around once we run out of input values
                // to allocate).
                //
                // The proof that each row of this procedure is unique is easy
                // using induction. Proving that every row is unique also shows
                // that the full test matrix has been covered.
                result[i][j] = inputs[j][
                    (i / (result.length / intervalDivisors[j])) %
                        inputs[j].length
                ];
            }
        }
        return result;
    }

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
