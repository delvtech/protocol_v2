// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console2.sol";
import "forge-std/Test.sol";

import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { MockERC20Permit } from "contracts/mocks/MockERC20Permit.sol";
import { MockTerm, MockTermCall } from "contracts/mocks/MockTerm.sol";
import { MockPool, MockPoolCall } from "contracts/mocks/MockPool.sol";

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
        //uint256 userBalance;
    }

    function testRegisterPoolId() public {
        startHoax(user);

        uint256[] memory inputs = new uint256[](4);
        inputs[0] = 0; // 0 case
        inputs[1] = TERM_END; //
        inputs[2] = 1e18; // general amount
        inputs[3] = (type(uint256).max / 1e18) + 1; // scaled div overflow in mu calc

        RegisterPoolIdTestCase[]
            memory testCases = _convertRegisterPoolIdTestCase(
                Utils.generateTestingMatrix(7, inputs)
            );

        for (uint256 i = 0; i < testCases.length; i++) {
            RegisterPoolIdTestCase memory testCase = testCases[i];
            _setupRegisterPoolIdTestCase(testCase);
            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedRegisterPoolIdError(testCase);

            if (testCaseIsError) {
                try
                    pool.registerPoolId(
                        testCase.poolId,
                        testCase.underlyingIn,
                        testCase.tStretch,
                        user,
                        testCase.maxTime,
                        testCase.maxLength
                    )
                {
                    _logRegisterPoolIdTestCase(
                        "Expected fail, test case passes",
                        i,
                        testCase
                    );
                    revert TestFail();
                } catch (bytes memory err) {
                    assertEq(err, expectedError);
                    if (!Utils.eq(err, expectedError)) {
                        _logRegisterPoolIdTestCase(
                            "Expected different failure reason",
                            i,
                            testCase
                        );
                        revert TestFail();
                    }
                }
            } else {
                _registerExpectedRegisterPoolIdEvents(testCase);
                try
                    pool.registerPoolId(
                        testCase.poolId,
                        testCase.underlyingIn,
                        testCase.tStretch,
                        user,
                        testCase.maxTime,
                        testCase.maxLength
                    )
                returns (uint256 mintedLpTokens) {
                    _validateRegisterPoolIdSuccess(testCase, mintedLpTokens);
                } catch (bytes memory err) {
                    _logRegisterPoolIdTestCase(
                        "Expected passing test, fails",
                        i,
                        testCase
                    );
                    revert TestFail();
                }
            }
        }
    }

    function _registerExpectedRegisterPoolIdEvents(
        RegisterPoolIdTestCase memory testCase
    ) internal {
        vm.expectEmit(true, true, true, true);
        emit MockTermCall.DepositUnlocked(
            testCase.underlyingIn,
            0,
            0,
            address(pool)
        );

        vm.expectEmit(true, false, false, false);
        emit MockPoolCall.PoolRegistered(testCase.poolId);
    }

    function _getExpectedRegisterPoolIdError(
        RegisterPoolIdTestCase memory testCase
    ) internal returns (bool testCaseIsError, bytes memory reason) {
        // where the input poolId is less than mined block timestamp
        if (testCase.poolId <= block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermExpired.selector)
            );
        }

        // setup phase defines existing term at this ID
        if (testCase.totalSupply > 0) {
            return (
                true,
                abi.encodeWithSelector(ElementError.PoolInitialized.selector)
            );
        }

        if (testCase.tStretch == 0) {
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.TimeStretchMustBeNonZero.selector
                )
            );
        }

        if (testCase.underlyingIn == 0) {
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.UnderlyingInMustBeNonZero.selector
                )
            );
        }

        // assembly division by zero in fixed point math
        if (testCase.sharesMinted == 0) {
            return (true, EMPTY_REVERT);
        }

        // NOTE Should this error case be reachable?
        if (
            (testCase.maxLength > 1 && testCase.maxTime == 0) ||
            testCase.maxTime < testCase.maxLength
        ) {
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.TWAROracle_MinTimeStepMustBeNonZero.selector
                )
            );
        }

        if (testCase.maxLength <= 1 && testCase.maxTime > 0) {
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.TWAROracle_IncorrectBufferLength.selector
                )
            );
        }

        // if (testCase.sharesMinted > type(uint128).max) {
        //     return bytes("OVERFLOW");
        // }

        // if (testCase.maxLength <= 1 && testCase.maxTime > 0) {
        //     vm.expectRevert(
        //         ElementError.TWAROracle_IncorrectBufferLength.selector
        //     );
        //     return true;
        // }

        // if (testCase.sharesMinted == 0) {
        //     vm.expectRevert(); // FixedPointMath assembly division error
        //     return true;
        // }
        return (false, new bytes(0));
    }

    function _validateRegisterPoolIdSuccess(
        RegisterPoolIdTestCase memory testCase,
        uint256 mintedLpTokens
    ) internal {
        // uint256 userUnderlyingBalance = underlying.balanceOf(user);
        // uint256 userLpBalanceBefore = pool.balanceOf(testCase.poolId, user);
        // uint256 poolTotalSupplyBefore = pool.totalSupply(testCase.poolId);
        // uint256 unlockedYTOnPoolBalanceBefore = term.balanceOf(
        //     term.UNLOCKED_YT_ID(),
        //     address(pool)
        // );

        // uint256 mintedLpTokens = pool.registerPoolId(
        //     testCase.poolId,
        //     testCase.underlyingIn,
        //     testCase.tStretch,
        //     user,
        //     testCase.maxTime,
        //     testCase.maxLength
        // );

        assertEq(
            underlying.balanceOf(user),
            0,
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
            pool.totalSupply(testCase.poolId),
            testCase.totalSupply + testCase.sharesMinted,
            "should create sharesMinted amount of LP tokens"
        );

        assertEq(
            pool.balanceOf(testCase.poolId, user),
            testCase.sharesMinted,
            "LP tokens should be minted to the user"
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
        underlying.mint(user, testCase.underlyingIn);
        pool.setTotalSupply(testCase.poolId, testCase.totalSupply);

        term.setDepositUnlockedReturnValues(
            testCase.underlyingIn,
            testCase.sharesMinted
        );
    }

    function _convertRegisterPoolIdTestCase(uint256[][] memory rawTestCases)
        internal
        view
        returns (RegisterPoolIdTestCase[] memory testCases)
    {
        testCases = new RegisterPoolIdTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 7,
                "Raw test case must have length of 7"
            );

            // Error cases for poolId
            // 1. poolId == block.timestamp
            // 2. poolId < block.timestamp
            // All other cases should be specified by TERM_END
            uint256 _poolId = rawTestCases[i][0] == 0
                ? 0
                : rawTestCases[i][0] == 1e18
                ? block.timestamp
                : rawTestCases[i][0];

            // Failing case input for maxTime is only 0 so conforming to 5 for
            // all other cases
            uint16 _maxTime = rawTestCases[i][3] == 0 ? 0 : 5;

            // Failing case input for maxLength is 0 or 1 so conforming to those
            // where input is 0 or TERM_END and then 5 in all other cases
            uint16 _maxLength = rawTestCases[i][4] == 0
                ? 0
                : rawTestCases[i][4] == TERM_END
                ? 1
                : 5;

            testCases[i] = RegisterPoolIdTestCase({
                poolId: _poolId,
                underlyingIn: rawTestCases[i][1],
                tStretch: uint32(rawTestCases[i][2]),
                maxTime: uint16(rawTestCases[i][3]),
                maxLength: uint16(rawTestCases[i][4]),
                totalSupply: rawTestCases[i][5],
                sharesMinted: rawTestCases[i][6]
            });
        }
    }

    function _logRegisterPoolIdTestCase(
        string memory prelude,
        uint256 index,
        RegisterPoolIdTestCase memory testCase
    ) internal {
        console2.log("    Pool.registerPoolId Test #%s :: %s", index, prelude);
        console2.log("    -------------------------------    ");
        console2.log("    poolId           = ", testCase.poolId);
        console2.log("    underlyingIn     = ", testCase.underlyingIn);
        console2.log("    tStretch         = ", testCase.tStretch);
        console2.log("    maxTime          = ", testCase.maxTime);
        console2.log("    maxLength        = ", testCase.maxLength);
        console2.log("    totalSupply      = ", testCase.totalSupply);
        console2.log("    sharesMinted     = ", testCase.sharesMinted);
        console2.log("");
    }
}
