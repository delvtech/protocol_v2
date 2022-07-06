// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "hardhat/console.sol";
import "contracts/libraries/TypedFixedPointMathLib.sol";
import "contracts/libraries/YieldSpaceMathLib.sol";

contract MockYieldSpaceMath {
    function calculateOutGivenIn(
        UFixedPoint shareReserves,
        UFixedPoint bondReserves,
        UFixedPoint totalSupply,
        UFixedPoint bondIn,
        UFixedPoint t,
        UFixedPoint s,
        UFixedPoint c,
        UFixedPoint mu,
        bool isBondOut
    ) public view returns (UFixedPoint result) {
        uint256 startGas = gasleft();
        result = YieldSpaceMathLib.calculateOutGivenIn(
            shareReserves,
            bondReserves,
            totalSupply,
            bondIn,
            t,
            s,
            c,
            mu,
            isBondOut
        );
        console.log("gasUsed", startGas - gasleft());
    }
}
