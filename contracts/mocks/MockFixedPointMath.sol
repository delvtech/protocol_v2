// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "hardhat/console.sol";
import "contracts/libraries/FixedPointMath.sol";

contract MockFixedPointMath {
    function add(uint256 x, uint256 y) public view returns (uint256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMath.add(x, y);
        console.log("gasUsed", startGas - gasleft());
    }

    function sub(uint256 x, uint256 y) public view returns (uint256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMath.sub(x, y);
        console.log("gasUsed", startGas - gasleft());
    }

    function pow(uint256 x, uint256 y) public view returns (uint256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMath.pow(x, y);
        console.log("gasUsed", startGas - gasleft());
    }

    function exp(int256 x) public view returns (int256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMath.exp(x);
        console.log("gasUsed", startGas - gasleft());
    }

    function ln(int256 x) public view returns (int256 result) {
        uint256 startGas = gasleft();
        result = FixedPointMath.ln(x);
        console.log("gasUsed", startGas - gasleft());
    }
}
