// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { ERC4626Term, IERC4626 } from "contracts/ERC4626Term.sol";
import { Pool, ITerm, IERC20, FixedPointMath, ElementError } from "contracts/Pool.sol";

import { Utils } from "../Utils.sol";
import { PoolTest } from "./PoolUtils.sol";

contract PoolTest__registerPoolId is PoolTest {
    function setUp() public {
        PoolTest.Env memory env = PoolTest.Env({
            vaultSharePrice: 0.9e6,
            vaultShareSupply: 9_000_000e6,
            maxReserve: 100_000e6,
            underlyingToLock: 100_000e6,
            underlyingToLP: 1_000_000e6,
            termDurationPassed: 0.5e18, // 50%
            averageYieldAcrossTerm: 0.1e18 // 10%
        });
        initEnv(env);

        vm.startPrank(user);
        USDC.mint(user, 100_000e6);
        USDC.approve(address(pool), type(uint256).max);
    }

    function test__buy() public {
        // uint256 underlying = 1000e6;
        // uint256 pt = pool.tradeBonds(
        //     TERM_END,
        //     underlying,
        //     underlying,
        //     user,
        //     true
        // );
    }
}
