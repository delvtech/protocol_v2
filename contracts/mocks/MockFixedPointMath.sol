// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "contracts/libraries/TypedFixedPointMathLib.sol";
import "contracts/libraries/FixedPointMathLib.sol";

contract MockFixedPointMath {
    function add(uint256 x, uint256 y) public view returns (uint256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMathLib.add(x, y);
        console.log("gasUsed", startGas - gasleft());
    }

    function sub(uint256 x, uint256 y) public view returns (uint256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMathLib.sub(x, y);
        console.log("gasUsed", startGas - gasleft());
    }

    function pow(uint256 x, uint256 y) public view returns (uint256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMathLib.pow(x, y);
        console.log("gasUsed", startGas - gasleft());
    }

    function exp(int256 x) public view returns (int256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMathLib.exp(x);
        console.log("gasUsed", startGas - gasleft());
    }

    function ln(int256 x) public view returns (int256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMathLib.ln(x);
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

    function addTyped(UFixedPoint x, UFixedPoint y)
        public
        view
        returns (UFixedPoint result)
    {
        uint256 startGas = gasleft();
        result = TypedFixedPointMathLib.add(x, y);
        console.log("gasUsed", startGas - gasleft());
    }

    function subTyped(UFixedPoint x, UFixedPoint y)
        public
        view
        returns (UFixedPoint result)
    {
        uint256 startGas = gasleft();
        result = TypedFixedPointMathLib.sub(x, y);
        console.log("gasUsed", startGas - gasleft());
    }
}
