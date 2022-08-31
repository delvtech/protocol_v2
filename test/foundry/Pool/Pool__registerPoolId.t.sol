// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { MockERC4626, ERC20 } from "contracts/mocks/MockERC4626.sol";
import { MockERC20Permit } from "contracts/mocks/MockERC20Permit.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { ERC4626Term, IERC4626 } from "contracts/ERC4626Term.sol";
import { Pool, ITerm, IERC20, FixedPointMath, ElementError } from "contracts/Pool.sol";

import { Utils } from "../Utils.sol";
import { PoolTest } from "./PoolUtils.sol";

contract PoolTest__registerPoolId is PoolTest {
    // success case - no oracle initialization
    function test__no_oracle_init() public {
        uint256 underlying = 10_000e6;

        uint256 userUnderlyingPreBalance = USDC.balanceOf(user);
        uint256 userLpPreBalance = pool.balanceOf(TERM_END, user);

        (uint128 preShares, uint128 preBonds) = pool.reserves(TERM_END);

        uint256 estMintedShares = Utils.underlyingAsUnlockedShares(
            term,
            underlying
        );
        uint256 estMu = FixedPointMath.divDown(
            underlying * 10e12,
            estMintedShares * 10e12
        );

        uint256 sharesMinted = pool.registerPoolId(
            TERM_END,
            underlying,
            T_STRETCH,
            user,
            0,
            0
        );

        uint256 userUnderlyingPostBalance = USDC.balanceOf(user);
        uint256 userLpPostBalance = pool.balanceOf(TERM_END, user);

        uint256 userUnderlyingDiff = userUnderlyingPreBalance -
            userUnderlyingPostBalance;
        uint256 userLpDiff = userLpPostBalance - userLpPreBalance;

        // User balances should be changed as expected
        assertEq(userUnderlyingDiff, underlying);
        assertEq(userLpDiff, estMintedShares);
        assertEq(sharesMinted, estMintedShares);

        // Shares should be added to the pool reserves
        (uint128 postShares, uint128 postBonds) = pool.reserves(TERM_END);
        assertEq(postShares - preShares, estMintedShares);
        assertEq(preBonds, postBonds);

        // buffer should not be initialized
        (, , , uint16 bufferMaxLength, ) = pool.readMetadataParsed(TERM_END);
        assertEq(bufferMaxLength, 0);

        // Pool parameters should be set correctly
        (uint32 tStretch, uint224 mu) = pool.parameters(TERM_END);
        assertEq(tStretch, T_STRETCH);
        assertEq(mu, estMu);
    }

    // success case - initialize oracle
    function test__oracle_init() public {
        pool.registerPoolId(TERM_END, 10_000e6, T_STRETCH, user, 5, 5);

        // buffer should be initialized
        (, , , uint16 bufferMaxLength, ) = pool.readMetadataParsed(TERM_END);
        assertEq(bufferMaxLength, 5);
    }

    // error case - register pool past expiry
    function test__beyond_expiry() public {
        // Fast forward to end of term + 1 second
        vm.warp(TERM_END + 1);
        vm.expectRevert(ElementError.TermExpired.selector);
        pool.registerPoolId(TERM_END, 10_000e6, T_STRETCH, user, 5, 5);
    }

    // error case - pool already initialized
    function test__pool_initialized() public {
        pool.registerPoolId(TERM_END, 10_000e6, T_STRETCH, user, 5, 5);
        vm.expectRevert(ElementError.PoolInitialized.selector);
        pool.registerPoolId(TERM_END, 10_000e6, T_STRETCH, user, 5, 5);
    }

    // error case - zero t-stretch
    function test__zero_tStretch() public {
        vm.expectRevert(ElementError.TimeStretchMustBeNonZero.selector);
        pool.registerPoolId(TERM_END, 10_000e6, 0, user, 5, 5);
    }
}
