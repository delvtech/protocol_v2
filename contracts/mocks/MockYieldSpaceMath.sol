// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "hardhat/console.sol";
import "contracts/libraries/YieldSpaceMath.sol";

contract MockYieldSpaceMath {
    function calculateOutGivenIn(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 totalSupply,
        uint256 bondIn,
        uint256 t,
        uint256 s,
        uint256 c,
        uint256 mu,
        bool isBondOut
    ) public view returns (uint256 result) {
        uint256 startGas = gasleft();
        result = YieldSpaceMath.calculateOutGivenIn(
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
