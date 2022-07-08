// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
library SafeCast {
    
    /// @notice Cast a uint256 to uint128, revert on overflow.
    /// @param  a The uint256 input variable to be downcasted.
    /// @return c The downcasted inteeger, type uint128.
    function toUint128(uint256 a) internal pure returns(uint128 c) {
        // Silently kills the function execution.
        // Fun to find the root cause of error.
        require((c = uint128(a)) == a);
    }

    /// @notice Cast a uint256 to int128, revert on overflow.
    /// @param  a The uint256 input variable to be downcasted.
    /// @return c The downcasted inteeger, type int128.
    function toInt128(uint256 a) internal pure returns(int128 c) {
        require(a < 2**255);
        // Silently kills the function execution.
        // Fun to find the root cause of error.
        require((c = int128(int256(a))) == int256(a));
    }

    /// @notice Cast a int256 to uint128, revert on overflow.
    /// @param  a The int256 input variable to be downcasted.
    /// @return c The downcasted inteeger, type int128.
    function toInt128(int256 a) internal pure returns(int128 c) {
        // Silently kills the function execution.
        // Fun to find the root cause of error.
        require((c = int128(a)) == a);
    }

}

