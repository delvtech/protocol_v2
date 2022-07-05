// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "hardhat/console.sol";
import "contracts/libraries/TypedFixedPointMathLib.sol";
import "contracts/libraries/YieldSpaceMathLib.sol";

contract MockYieldSpaceMath {
    function calculateBondOutGivenShareIn(
        UFixedPoint shareReserves,
        UFixedPoint bondReserves,
        UFixedPoint totalSupply,
        UFixedPoint shareIn,
        UFixedPoint t,
        UFixedPoint s,
        UFixedPoint c,
        UFixedPoint mu
    ) public view returns (UFixedPoint result) {
        uint256 startGas = gasleft();
        result = YieldSpaceMathLib.calculateBondOutGivenShareIn(
            shareReserves,
            bondReserves,
            totalSupply,
            shareIn,
            t,
            s,
            c,
            mu
        );
        console.log("gasUsed", startGas - gasleft());
    }

    function calculateShareOutGivenBondIn(
        UFixedPoint shareReserves,
        UFixedPoint bondReserves,
        UFixedPoint totalSupply,
        UFixedPoint bondIn,
        UFixedPoint t,
        UFixedPoint s,
        UFixedPoint c,
        UFixedPoint mu
    ) public view returns (UFixedPoint result) {
        uint256 startGas = gasleft();
        result = YieldSpaceMathLib.calculateShareOutGivenBondIn(
            shareReserves,
            bondReserves,
            totalSupply,
            bondIn,
            t,
            s,
            c,
            mu
        );
        console.log("gasUsed", startGas - gasleft());
    }
}
