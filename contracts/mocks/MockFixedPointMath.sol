// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "contracts/libraries/TypedFixedPointMathLib.sol";

contract MockFixedPointMath {
    function pow(UFixedPoint x, UFixedPoint y)
        public
        view
        returns (UFixedPoint result)
    {
        uint256 startGas = gasleft();
        result = TypedFixedPointMathLib.pow(x, y);
        console.log("gasUsed", startGas - gasleft());
    }
}
