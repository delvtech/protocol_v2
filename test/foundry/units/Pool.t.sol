// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console2.sol";
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

    // ------------------- name unit tests ------------------ //
    // ------------------- symbol unit tests ------------------ //
    // ------------------- registerPoolId unit tests ------------------ //

    struct RegisterPoolIdTestCase {
        // args
        uint256 poolId;
        uint256 underlyingIn;
        uint32 tStretch;
        uint16 minTime;
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

        // minTime
        inputs[3] = new uint256[](2);
        inputs[3][0] = 0;
        inputs[3][1] = 1;

        // maxLength
        inputs[4] = new uint256[](2);
        inputs[4][0] = 0;
        inputs[4][1] = 1;

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
                Utils.generateTestingMatrix(inputs)
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
                        testCase.minTime,
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
                    if (Utils.neq(bytes(err), expectedError)) {
                        _logRegisterPoolIdTestCase(
                            "Expected different failure reason (string)",
                            i,
                            testCase
                        );
                        assertEq(err, string(expectedError));
                        revert TestFail();
                    }
                } catch (bytes memory err) {
                    if (Utils.neq(err, expectedError)) {
                        _logRegisterPoolIdTestCase(
                            "Expected different failure reason (bytes)",
                            i,
                            testCase
                        );
                        assertEq(err, expectedError);
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
                        testCase.minTime,
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
        pure
        returns (RegisterPoolIdTestCase[] memory testCases)
    {
        testCases = new RegisterPoolIdTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            testCases[i] = RegisterPoolIdTestCase({
                poolId: rawTestCases[i][0],
                underlyingIn: rawTestCases[i][1],
                tStretch: uint32(rawTestCases[i][2]),
                minTime: uint16(rawTestCases[i][3]),
                maxLength: uint16(rawTestCases[i][4]),
                totalSupply: rawTestCases[i][5],
                sharesMinted: rawTestCases[i][6],
                sharesValue: rawTestCases[i][7],
                userBalance: rawTestCases[i][8]
            });
        }
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event DepositUnlocked(
        uint256 underlyingAmount,
        uint256 ptAmount,
        uint256 ptExpiry,
        address destination
    );
    event Update(
        uint256 poolId,
        uint128 newBondBalance,
        uint128 newSharesBalance
    );
    event Mint(uint256 tokenID, address to, uint256 amount);
    event InitializeBuffer(uint256 bufferId, uint16 minTime, uint16 maxLength);
    event PoolRegistered(uint256 indexed poolId);

    function _registerExpectedRegisterPoolIdEvents(
        RegisterPoolIdTestCase memory testCase
    ) internal {
        expectStrictEmit();
        emit Transfer(user, address(pool), testCase.underlyingIn);

        expectStrictEmit();
        emit DepositUnlocked(testCase.underlyingIn, 0, 0, address(pool));

        expectStrictEmit();
        emit Update(
            testCase.poolId,
            uint128(0),
            uint128(testCase.sharesMinted)
        );

        if (testCase.minTime > 0 || testCase.maxLength > 0) {
            expectStrictEmit();
            emit InitializeBuffer(
                testCase.poolId,
                testCase.minTime,
                testCase.maxLength
            );
        }

        expectStrictEmit();
        emit Mint(testCase.poolId, user, testCase.sharesMinted);

        expectStrictEmit();
        emit PoolRegistered(testCase.poolId);
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

        if (testCase.userBalance < testCase.underlyingIn) {
            return (true, bytes("ERC20: insufficient-balance"));
        }

        if (testCase.sharesValue > (type(uint256).max / 1e18)) {
            return (true, EMPTY_REVERT);
        }

        // assembly division by zero in fixed point math
        if (testCase.sharesMinted == 0) {
            return (true, EMPTY_REVERT);
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

        assertEq(
            pool.totalSupply(testCase.poolId),
            testCase.sharesMinted,
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
        console2.log("    minTime          = ", testCase.minTime);
        console2.log("    maxLength        = ", testCase.maxLength);
        console2.log("    totalSupply      = ", testCase.totalSupply);
        console2.log("    sharesMinted     = ", testCase.sharesMinted);
        console2.log("    sharesValue      = ", testCase.sharesValue);
        console2.log("    userBalance      = ", testCase.userBalance);
        console2.log("");
    }

    // ------------------- tradeBonds unit tests ------------------ //

    function testTradeBonds() public {
        startHoax(user);

        uint256[][] memory inputs = new uint256[][](9);

        // poolId
        inputs[0] = new uint256[](3);
        inputs[0][0] = 0;
        inputs[0][1] = block.timestamp;
        inputs[0][2] = TERM_END;

        // amount
        inputs[1] = new uint256[](2);
        inputs[1][0] = 0;
        inputs[1][1] = 1 ether;

        // minAmountOut
        inputs[2] = new uint256[](3);
        inputs[2][0] = 0;
        inputs[2][1] = 1 ether;
        inputs[2][2] = 2 ether;

        // isBuy - to be converted
        inputs[3] = new uint256[](2);
        inputs[3][0] = 0;
        inputs[3][1] = 1;

        // shareReserves
        inputs[4] = new uint256[](2);
        inputs[4][0] = 0;
        inputs[4][1] = 1 ether;

        // bondReserves
        inputs[5] = new uint256[](2);
        inputs[5][0] = 0;
        inputs[5][1] = 1 ether;

        // newShareReserves
        inputs[6] = new uint256[](3);
        inputs[6][0] = 0;
        inputs[6][1] = 1 ether;
        inputs[6][1] = 10 ether;

        // newBondReserves
        inputs[7] = new uint256[](3);
        inputs[7][0] = 0;
        inputs[7][1] = 1 ether;
        inputs[7][1] = 10 ether;

        // outputAmount
        inputs[8] = new uint256[](3);
        inputs[8][0] = 0;
        inputs[8][1] = 1 ether;
        inputs[8][1] = 2 ether;

        TradeBondsTestCase[] memory testCases = _convertTradeBondsTestCase(
            Utils.generateTestingMatrix2(inputs)
        );

        for (uint256 i = 0; i < testCases.length; i++) {
            TradeBondsTestCase memory testCase = testCases[i];
            _setupTradeBondsTestCase(testCase);
            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedTradeBondsError(testCase);

            if (testCaseIsError) {
                try
                    pool.tradeBonds(
                        testCase.poolId,
                        testCase.amount,
                        testCase.minAmountOut,
                        user,
                        testCase.isBuy
                    )
                {
                    _logTradeBondsTestCase(
                        "Expected fail, test case passes",
                        i,
                        testCase
                    );
                    revert TestFail();
                } catch (bytes memory err) {
                    if (Utils.neq(err, expectedError)) {
                        _logTradeBondsTestCase(
                            "Expected different failure reason (bytes)",
                            i,
                            testCase
                        );
                        assertEq(err, expectedError);
                        revert TestFail();
                    }
                }
            } else {
                _registerExpectedTradeBondsEvents(testCase);
                try
                    pool.tradeBonds(
                        testCase.poolId,
                        testCase.amount,
                        testCase.minAmountOut,
                        user,
                        testCase.isBuy
                    )
                returns (uint256 outputAmount) {
                    assertEq(outputAmount, testCase.outputAmount);
                } catch (bytes memory err) {
                    _logTradeBondsTestCase(
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

    struct TradeBondsTestCase {
        // args
        uint256 poolId;
        uint256 amount;
        uint256 minAmountOut;
        bool isBuy;
        // state
        uint128 shareReserves;
        uint128 bondReserves;
        uint128 newShareReserves;
        uint128 newBondReserves;
        uint256 outputAmount;
    }

    function _convertTradeBondsTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (TradeBondsTestCase[] memory testCases)
    {
        testCases = new TradeBondsTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            testCases[i] = TradeBondsTestCase({
                poolId: rawTestCases[i][0],
                amount: rawTestCases[i][1],
                minAmountOut: rawTestCases[i][2],
                isBuy: rawTestCases[i][3] > 0,
                shareReserves: uint128(rawTestCases[i][4]),
                bondReserves: uint128(rawTestCases[i][5]),
                newShareReserves: uint128(rawTestCases[i][6]),
                newBondReserves: uint128(rawTestCases[i][7]),
                outputAmount: rawTestCases[i][8]
            });
        }
    }

    function _getExpectedTradeBondsError(TradeBondsTestCase memory testCase)
        internal
        view
        returns (bool testCaseIsError, bytes memory reason)
    {
        // where the input poolId is less than mined block timestamp
        if (testCase.poolId <= block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermExpired.selector)
            );
        }

        if (testCase.shareReserves == 0 && testCase.bondReserves == 0) {
            return (
                true,
                abi.encodeWithSelector(ElementError.PoolNotInitialized.selector)
            );
        }

        if (testCase.outputAmount < testCase.minAmountOut)
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.ExceededSlippageLimit.selector
                )
            );

        return (false, new bytes(0));
    }

    function _setupTradeBondsTestCase(TradeBondsTestCase memory testCase)
        internal
    {
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

        pool.setReserves(
            testCase.poolId,
            testCase.shareReserves,
            testCase.bondReserves
        );
        pool.setMockTradeReturnValues(
            testCase.newShareReserves,
            testCase.newBondReserves,
            testCase.outputAmount
        );
    }

    event BuyBonds(
        uint256 poolId,
        uint256 amount,
        uint128 reserveShares,
        uint128 reserveBonds,
        address receiver
    );

    event SellBonds(
        uint256 poolId,
        uint256 amount,
        uint128 reserveShares,
        uint128 reserveBonds,
        address receiver
    );

    event BondsTraded(
        uint256 indexed poolId,
        address indexed receiver,
        bool indexed isBuy,
        uint256 amountIn,
        uint256 amountOut
    );

    function _registerExpectedTradeBondsEvents(
        TradeBondsTestCase memory testCase
    ) internal {
        if (testCase.isBuy) {
            expectStrictEmit();
            emit BuyBonds(
                testCase.poolId,
                testCase.amount,
                testCase.shareReserves,
                testCase.bondReserves,
                user
            );
        } else {
            expectStrictEmit();
            emit SellBonds(
                testCase.poolId,
                testCase.amount,
                testCase.shareReserves,
                testCase.bondReserves,
                user
            );
        }

        expectStrictEmit();
        emit Update(
            testCase.poolId,
            testCase.newBondReserves,
            testCase.newShareReserves
        );

        expectStrictEmit();
        emit BondsTraded(
            testCase.poolId,
            user,
            testCase.isBuy,
            testCase.amount,
            testCase.outputAmount
        );
    }

    function _logTradeBondsTestCase(
        string memory prelude,
        uint256 index,
        TradeBondsTestCase memory testCase
    ) internal view {
        console2.log("    Pool.tradeBonds Test #%s :: %s", index, prelude);
        console2.log("    -----------------------------------------------    ");
        console2.log("    poolId           = ", testCase.poolId);
        console2.log("    amount           = ", testCase.amount);
        console2.log("    minAmountOut     = ", testCase.minAmountOut);
        console2.log("    isBuy            = ", testCase.isBuy);
        console2.log("    shareReserves    = ", testCase.shareReserves);
        console2.log("    bondReserves     = ", testCase.bondReserves);
        console2.log("    outputAmount     = ", testCase.outputAmount);
        console2.log("");
    }
}
