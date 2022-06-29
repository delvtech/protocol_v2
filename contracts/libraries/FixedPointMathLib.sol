/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

/// @notice Arithmetic library with operations for fixed-point numbers.
/// @author Element Finance
library FixedPointMathLib {
    // TODO: Why not use remco's version? https://xn--2-umb.com/21/muldiv

    /// @dev Credit to Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(d != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(d)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // Divide z by the d.
            z := div(z, d)
        }
    }

    /// @dev Credit to Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(d != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(d)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // First, divide z - 1 by the d and add 1.
            // We allow z - 1 to underflow if z is 0, because we multiply the
            // end result by 0 if z is zero, ensuring we return 0 if z is zero.
            z := mul(iszero(iszero(z)), add(div(sub(z, 1), d), 1))
        }
    }
}
