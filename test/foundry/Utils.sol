// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC4626Term } from "contracts/ERC4626Term.sol";

library Utils {
    function eq(bytes memory b1, bytes memory b2) public returns (bool) {
        return
            keccak256(abi.encodePacked(b1)) == keccak256(abi.encodePacked(b2));
    }

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
    //         inputs for a given number of rows.
    // @dev In order to generate the full testing matrix, we need to generate
    //      cases for each value that use all of the input values. In order
    //      to do this, we segment the set of test cases into subsets for each
    //      entry
    // @param rows If we think of individual test cases as columns, then we
    //        can think about rows as the individual variables of the test
    //        case.
    // @param inputs An array of uint256 values that will be used to populate
    //        the individual entries of the test cases. Increasing the number
    //        of inputs dramatically increases the amount of test cases that
    //        will be generated, so it's important to limit the amount of
    //        inputs to a small number of meaningful values. We use uint256 for
    //        generality, since uint256 can be converted to small width types.
    // @return The full testing matrix.
    function generateTestingMatrix(uint256 rows, uint256[] memory inputs)
        internal
        pure
        returns (uint256[][] memory result)
    {
        // Ensure that the input values are unique.
        for (uint256 i = 1; i < inputs.length; i++) {
            require(
                inputs[i - 1] < inputs[i],
                "utils: test inputs aren't sorted."
            );
        }

        // Generate the full testing matrix.
        result = new uint256[][](inputs.length**rows);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = new uint256[](rows);
            for (uint256 j = 0; j < rows; j++) {
                // The idea behind this calculation is that we split the set of
                // test cases into sections and assign one input value to each
                // section. For the first row, we'll create {inputs.length}
                // sections and assign these values to sections linearly. For
                // row k, we'll create inputs.length ** (k + 1) sections, and
                // we'll assign the 0th input to the first section, the 1st
                // input to the second section, and continue this process
                // (wrapping around once we run out of input values to allocate).
                //
                // The proof that each row of this procedure is unique is easy
                // using induction. Proving that every row is unique also shows
                // that the full test matrix has been covered.
                result[i][j] = inputs[
                    (i / (result.length / (inputs.length**(j + 1)))) %
                        inputs.length
                ];
            }
        }
        return result;
    }
}
