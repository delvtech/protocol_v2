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
    // success case - general flow
    function test__general_flow() public {
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
            5,
            5
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

        // Pool parameters should be set correctly
        (uint32 tStretch, uint224 mu) = pool.parameters(TERM_END);
        assertEq(tStretch, T_STRETCH);
        assertEq(mu, estMu);
    }

    // initializes the oracle
    function test__oracle_initialization(uint16 maxTime, uint16 maxLength)
        public
    {
        uint16 expectedMaxLength = maxLength;

        if (maxLength <= 1 && !(maxLength == 0 && maxTime == 0)) {
            vm.expectRevert(
                ElementError.TWAROracle_IncorrectBufferLength.selector
            );
            expectedMaxLength = 0;
        } else if (maxLength > maxTime) {
            vm.expectRevert(
                ElementError.TWAROracle_MinTimeStepMustBeNonZero.selector
            );
            expectedMaxLength = 0;
        }

        pool.registerPoolId(
            TERM_END,
            10_000e6,
            T_STRETCH,
            user,
            maxTime,
            maxLength
        );

        (, , , uint16 bufferMaxLength, ) = pool.readMetadataParsed(TERM_END);
        assertEq(bufferMaxLength, expectedMaxLength);
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

    // should emit PoolRegistered event correctly
    event PoolRegistered(uint256 indexed poolId);

    function test__emits_pool_registered_event() public {
        vm.expectEmit(true, false, false, false);
        emit PoolRegistered(TERM_END);
        pool.registerPoolId(TERM_END, 10_000e6, T_STRETCH, user, 5, 5);
    }

    // should emit Sync event correctly
    event Sync(
        uint256 indexed poolId,
        uint256 bondReserve,
        uint256 shareReserve
    );

    function test__emits_sync_event() public {
        uint256 underlying = 10_000e6;
        uint256 shares = Utils.underlyingAsUnlockedShares(term, underlying);

        vm.expectEmit(true, true, true, false);
        emit Sync(TERM_END, underlying, 1);
        pool.registerPoolId(TERM_END, underlying, T_STRETCH, user, 5, 5);
    }
}
