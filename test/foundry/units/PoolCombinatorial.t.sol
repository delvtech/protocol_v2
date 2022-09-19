// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import "forge-std/Test.sol";

import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { MockERC20Permit } from "contracts/mocks/MockERC20Permit.sol";
import { MockTerm } from "contracts/mocks/MockTerm.sol";
import { MockPool } from "contracts/mocks/MockPool.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ITerm } from "contracts/interfaces/ITerm.sol";

import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { ElementError } from "contracts/libraries/Errors.sol";

import { ElementTest } from "test/ElementTest.sol";
import { Utils } from "test/Utils.sol";

contract PoolTest is ElementTest {
    ForwarderFactory factory;
    MockERC20Permit underlying;
    MockTerm term;
    MockPool pool;

    address user = makeAddress("user");
    address governance = makeAddress("governance");

    uint256 TRADE_FEE = 1;
    uint256 TERM_END;

    function setUp() public {
        factory = new ForwarderFactory();
        vm.warp(2000);
        vm.roll(2);
        TERM_END = block.timestamp + YEAR;
    }

    // ------------------- constructor unit tests ------------------ //
    // ------------------- name unit tests ------------------ //
    // ------------------- symbol unit tests ------------------ //
    // ------------------- registerPoolId unit tests ------------------ //

    event PoolRegistered(uint256 indexed poolId);

    struct RegisterPoolIdTestCase {
        // args
        uint256 poolId;
        uint256 underlyingIn;
        uint32 tStretch;
        uint16 maxTime;
        uint16 maxLength;
        // state vars
        uint256 totalSupply;
        uint256 sharesMinted;
        uint256 userBalance;
    }

    function testRegisterPoolId() public {
        startHoax(user);

        uint256[] memory inputs = new uint256[](3);
        inputs[0] = 0; // 0 case
        inputs[1] = 1; // 1 maxLength initialize buffer error
        inputs[2] = TERM_END; // for fail case of prev term
        //inputs[3] = 1e18; // general amount
        //inputs[4] = (type(uint256).max / 1e18) + 1; // scaled div overflow in mu calc

        RegisterPoolIdTestCase[]
            memory testCases = _generateRegisterPoolIdTestCase(
                Utils.generateTestingMatrix(8, inputs)
            );

        for (uint256 i = 0; i < testCases.length; i++) {
            RegisterPoolIdTestCase memory testCase = testCases[i];
            _setupRegisterPoolIdTestCase(testCase);

            if (_validateRegisterPoolIdError(testCase)) {
                _logRegisterPoolIdTestCase(i, "error case", testCase);
                pool.registerPoolId(
                    testCase.poolId,
                    testCase.underlyingIn,
                    testCase.tStretch,
                    user,
                    testCase.maxTime,
                    testCase.maxLength
                );
            } else {
                _logRegisterPoolIdTestCase(i, "success case", testCase);
                _validateRegisterPoolIdSuccess(testCase);
            }
        }
    }

    function _validateRegisterPoolIdError(
        RegisterPoolIdTestCase memory testCase
    ) internal returns (bool) {
        // where the input poolId is less than mined block timestamp
        if (testCase.poolId <= block.timestamp) {
            vm.expectRevert(ElementError.TermExpired.selector);
            return true;
        }

        // setup phase defines existing term at this ID
        if (testCase.poolId == TERM_END) {
            vm.expectRevert(ElementError.PoolInitialized.selector);
            return true;
        }

        if (testCase.tStretch == 0) {
            vm.expectRevert(ElementError.PoolInitialized.selector);
            return true;
        }

        if (testCase.underlyingIn == 0) {
            vm.expectRevert(ElementError.UnderlyingInMustBeNonZero.selector);
            return true;
        }

        if (testCase.maxLength <= 1 && testCase.maxTime > 0) {
            vm.expectRevert(
                ElementError.TWAROracle_IncorrectBufferLength.selector
            );
            return true;
        }

        if (testCase.sharesMinted == 0) {
            vm.expectRevert(); // FixedPointMath assembly division error
            return true;
        }
        return false;
    }

    function _validateRegisterPoolIdSuccess(
        RegisterPoolIdTestCase memory testCase
    ) internal {
        uint256 userUnderlyingBalance = underlying.balanceOf(user);
        uint256 userLpBalanceBefore = pool.balanceOf(testCase.poolId, user);
        uint256 poolTotalSupplyBefore = pool.totalSupply(testCase.poolId);
        uint256 unlockedYTOnPoolBalanceBefore = term.balanceOf(
            term.UNLOCKED_YT_ID(),
            address(pool)
        );

        vm.expectEmit(true, false, false, false);
        emit PoolRegistered(testCase.poolId);

        uint256 mintedLpTokens = pool.registerPoolId(
            testCase.poolId,
            testCase.underlyingIn,
            testCase.tStretch,
            user,
            testCase.maxTime,
            testCase.maxLength
        );

        assertEq(
            underlying.balanceOf(user),
            userUnderlyingBalance - testCase.underlyingIn,
            "user underlying balance should decrease by amount of underlyingIn"
        );

        (uint128 shares, uint128 bonds) = pool.reserves(testCase.poolId);
        assertEq(
            shares,
            uint128(testCase.sharesMinted),
            "reserve shares should equal minted shares"
        );
        assertEq(bonds, 0, "reserve bonds should be 0");

        (, , , uint16 bufferMaxLength, ) = pool.readMetadataParsed(
            testCase.poolId
        );
        if (testCase.maxTime > 0 || testCase.maxLength > 0) {
            assertEq(
                bufferMaxLength,
                testCase.maxLength,
                "Oracle should be initialized"
            );
        } else {
            assertEq(bufferMaxLength, 0, "Oracle should not be initialized");
        }

        // As of writing we only test 18 point considering an underlying token
        // of 18 decimals
        uint256 derivedMu = FixedPointMath.divDown(
            testCase.underlyingIn,
            testCase.sharesMinted
        );
        (uint32 tStretch, uint224 mu) = pool.parameters(testCase.poolId);
        assertEq(
            tStretch,
            testCase.tStretch,
            "tStretch parameter should match input"
        );
        assertEq(mu, derivedMu, "mu paramater should be derived correctly");

        uint256 poolTotalSupplyAfter = pool.totalSupply(testCase.poolId);
        assertEq(
            poolTotalSupplyAfter - poolTotalSupplyBefore,
            testCase.totalSupply + testCase.sharesMinted,
            "should create sharesMinted amount of LP tokens"
        );

        uint256 userLpBalanceAfter = pool.balanceOf(testCase.poolId, user);
        assertEq(
            userLpBalanceAfter - userLpBalanceBefore,
            testCase.sharesMinted,
            "LP tokens should be minted to the recipient"
        );

        uint256 unlockedYTOnPoolBalanceAfter = term.balanceOf(
            term.UNLOCKED_YT_ID(),
            address(pool)
        );
        assertEq(
            unlockedYTOnPoolBalanceAfter - unlockedYTOnPoolBalanceBefore,
            testCase.sharesMinted,
            "Unlocked shares should be minted to the pool"
        );

        assertEq(
            mintedLpTokens,
            testCase.sharesMinted,
            "output value should equal minted shares"
        );
    }

    function _setupRegisterPoolIdTestCase(
        RegisterPoolIdTestCase memory testCase
    ) internal {
        underlying = new MockERC20Permit("Test", "TEST", 18);
        term = new MockTerm(
            factory.ERC20LINK_HASH(),
            address(factory),
            IERC20(underlying),
            governance
        );
        pool = new MockPool(
            ITerm(address(term)),
            IERC20(address(underlying)),
            TRADE_FEE,
            factory.ERC20LINK_HASH(),
            governance,
            address(factory)
        );

        underlying.approve(address(pool), type(uint256).max);

        // register previous pool
        underlying.mint(user, 1e18);
        term.setDepositReturnValues(0.9e18, 1e18);
        pool.registerPoolId(TERM_END, 1e18, 10245, user, 5, 5);

        underlying.mint(user, testCase.userBalance);
        pool.setTotalSupply(testCase.poolId, testCase.totalSupply);

        term.setDepositReturnValues(
            testCase.sharesMinted,
            testCase.underlyingIn
        );
    }

    function _generateRegisterPoolIdTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (RegisterPoolIdTestCase[] memory testCases)
    {
        testCases = new RegisterPoolIdTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 8,
                "Raw test case must have length of 8."
            );
            testCases[i] = RegisterPoolIdTestCase({
                poolId: rawTestCases[i][0],
                underlyingIn: rawTestCases[i][1],
                tStretch: uint32(rawTestCases[i][2]),
                maxTime: uint16(rawTestCases[i][3]) == type(uint16).max
                    ? 5
                    : uint16(rawTestCases[i][3]),
                maxLength: uint16(rawTestCases[i][4]) == type(uint16).max
                    ? 5
                    : uint16(rawTestCases[i][4]),
                totalSupply: rawTestCases[i][5],
                sharesMinted: rawTestCases[i][6],
                userBalance: rawTestCases[i][7]
            });
        }
    }

    function _logRegisterPoolIdTestCase(
        uint256 index,
        string memory prelude,
        RegisterPoolIdTestCase memory testCase
    ) internal {
        console.log("    Pool.registerPoolId Test # %s :: %s", index, prelude);
        console.log("    -------------------------------    ");
        console.log("    poolId           = ", testCase.poolId);
        console.log("    underlyingIn     = ", testCase.underlyingIn);
        console.log("    tStretch         = ", testCase.tStretch);
        console.log("    maxTime          = ", testCase.maxTime);
        console.log("    maxLength        = ", testCase.maxLength);
        console.log("    totalSupply      = ", testCase.totalSupply);
        console.log("    sharesMinted     = ", testCase.sharesMinted);
        console.log("");
    }
}
