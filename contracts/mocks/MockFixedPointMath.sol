// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "hardhat/console.sol";
import "contracts/libraries/TypedFixedPointMathLib.sol";
import "contracts/libraries/FixedPointMathLib.sol";

contract MockFixedPointMath {
    function pow(uint256 x, uint256 y) public view returns (uint256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMathLib.pow(x, y);
        console.log("gasUsed", startGas - gasleft());
    }

    function powTyped(UFixedPoint x, UFixedPoint y)
        public
        view
        returns (UFixedPoint result)
    {
        uint256 startGas = gasleft();
        result = TypedFixedPointMathLib.pow(x, y);
        console.log("gasUsed", startGas - gasleft());
    }
}
