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
        uint256 sharesValue;
        uint256 userBalance;
    }

    function testRegisterPoolId() public {
        startHoax(user);

        uint256[][] memory inputs = new uint256[][](9);
        // poolId
        inputs[0] = new uint256[](3);
        inputs[0][0] = 0;
        inputs[0][1] = block.timestamp;
        inputs[0][2] = TERM_END;

        // underlyingIn
        inputs[1] = new uint256[](2);
        inputs[1][0] = 0;
        inputs[1][1] = 1 ether;

        // tStretch
        inputs[2] = new uint256[](2);
        inputs[2][0] = 0;
        inputs[2][1] = 10245;

        // maxTime
        inputs[3] = new uint256[](3);
        inputs[3][0] = 0;
        inputs[3][1] = 1;
        inputs[3][2] = 5;

        // maxLength
        inputs[4] = new uint256[](3);
        inputs[4][0] = 0;
        inputs[4][1] = 1;
        inputs[4][2] = 5;

        // totalSupply
        inputs[5] = new uint256[](2);
        inputs[5][0] = 0;
        inputs[5][1] = 1 ether;

        // sharesMinted
        inputs[6] = new uint256[](2);
        inputs[6][0] = 0;
        inputs[6][1] = 1 ether;

        // sharesValue
        inputs[7] = new uint256[](3);
        inputs[7][0] = 0;
        inputs[7][1] = 1 ether;
        inputs[7][2] = (type(uint256).max / 1e18) + 1;

        // userBalance
        inputs[8] = new uint256[](2);
        inputs[8][0] = 0;
        inputs[8][1] = 1 ether;

        RegisterPoolIdTestCase[]
            memory testCases = _convertRegisterPoolIdTestCase(
                Utils.generateTestingMatrix2(inputs)
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
                } catch Error(string memory err) {
                    assertEq(err, string(expectedError));
                    if (!Utils.eq(bytes(err), expectedError)) {
                        _logRegisterPoolIdTestCase(
                            "Expected different failure reason (string)",
                            i,
                            testCase
                        );
                        revert TestFail();
                    }
                } catch (bytes memory err) {
                    assertEq(err, expectedError);
                    if (!Utils.eq(err, expectedError)) {
                        _logRegisterPoolIdTestCase(
                            "Expected different failure reason (bytes)",
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
                } catch {
                    _logRegisterPoolIdTestCase(
                        "Expected passing test, fails",
                        i,
                        testCase
                    );
                    revert TestFail();
                }
            }
        }
        console.log("###    %s combinations passing    ###", testCases.length);
    }

    function _convertRegisterPoolIdTestCase(uint256[][] memory rawTestCases)
        internal
        view
        returns (RegisterPoolIdTestCase[] memory testCases)
    {
        testCases = new RegisterPoolIdTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            testCases[i] = RegisterPoolIdTestCase({
                poolId: rawTestCases[i][0],
                underlyingIn: rawTestCases[i][1],
                tStretch: uint32(rawTestCases[i][2]),
                maxTime: uint16(rawTestCases[i][3]),
                maxLength: uint16(rawTestCases[i][4]),
                totalSupply: rawTestCases[i][5],
                sharesMinted: rawTestCases[i][6],
                sharesValue: rawTestCases[i][7],
                userBalance: rawTestCases[i][8]
            });
        }
    }

    event Transfer(address indexed from, address indexed to, uint256 value);

    function _registerExpectedRegisterPoolIdEvents(
        RegisterPoolIdTestCase memory testCase
    ) internal {
        vm.expectEmit(true, true, true, false);
        emit Transfer(user, address(pool), testCase.underlyingIn);

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
    ) internal view returns (bool testCaseIsError, bytes memory reason) {
        // where the input poolId is less than mined block timestamp
        if (testCase.poolId <= block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermExpired.selector)
            );
        }

        // implies that we have registered a pool previously
        if (testCase.totalSupply > 0 || testCase.poolId == TERM_END + 1) {
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

        if (testCase.userBalance < testCase.underlyingIn) {
            return (true, bytes("ERC20: insufficient-balance"));
        }

        // Will fail as underlyinIn is mapped to sharesValue which in the mu
        // calculation will do a scaled division and will overflow in conditions
        // where the normalized value is an exceptionally high value
        if (testCase.sharesValue > (type(uint256).max / 1e18)) {
            return (true, EMPTY_REVERT);
        }

        // assembly division by zero in fixed point math
        if (testCase.sharesMinted == 0) {
            return (true, EMPTY_REVERT);
        }

        if (
            (testCase.maxLength == 0 && testCase.maxTime > 0) ||
            (testCase.maxLength == 1)
        ) {
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.TWAROracle_IncorrectBufferLength.selector
                )
            );
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

        return (false, new bytes(0));
    }

    function _validateRegisterPoolIdSuccess(
        RegisterPoolIdTestCase memory testCase,
        uint256 mintedLpTokens
    ) internal {
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
            testCase.sharesValue,
            testCase.sharesMinted
        );
        (uint32 tStretch, uint224 mu) = pool.parameters(testCase.poolId);
        assertEq(
            tStretch,
            testCase.tStretch,
            "tStretch parameter should match input"
        );
        assertEq(mu, derivedMu, "mu paramater should be derived correctly");

        assertEq(
            pool.totalSupply(testCase.poolId),
            testCase.totalSupply + testCase.sharesMinted,
            "should create sharesMinted amount of LP tokens"
        );

        if (pool.balanceOf(testCase.poolId, user) != testCase.sharesMinted) {
            _logRegisterPoolIdTestCase("", 1, testCase);
        }

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

        underlying.mint(user, testCase.userBalance);
        pool.setTotalSupply(testCase.poolId, testCase.totalSupply);

        term.setDepositUnlockedReturnValues(
            testCase.sharesValue,
            testCase.sharesMinted
        );
    }

    function _logRegisterPoolIdTestCase(
        string memory prelude,
        uint256 index,
        RegisterPoolIdTestCase memory testCase
    ) internal view {
        console2.log("    Pool.registerPoolId Test #%s :: %s", index, prelude);
        console2.log("    -----------------------------------------------    ");
        console2.log("    poolId           = ", testCase.poolId);
        console2.log("    underlyingIn     = ", testCase.underlyingIn);
        console2.log("    tStretch         = ", testCase.tStretch);
        console2.log("    maxTime          = ", testCase.maxTime);
        console2.log("    maxLength        = ", testCase.maxLength);
        console2.log("    totalSupply      = ", testCase.totalSupply);
        console2.log("    sharesMinted     = ", testCase.sharesMinted);
        console2.log("    sharesValue      = ", testCase.sharesValue);
        console2.log("    userBalance      = ", testCase.userBalance);

        console2.log("");
    }
}
