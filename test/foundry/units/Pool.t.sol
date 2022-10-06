// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console2.sol";
import "forge-std/Test.sol";

import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { LP } from "contracts/LP.sol";

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
                    _logRegisterPoolIdTestCase(testCase);
                    revert ExpectedFailingTestPasses(expectedError);
                } catch Error(string memory err) {
                    if (Utils.neq(bytes(err), expectedError)) {
                        _logRegisterPoolIdTestCase(testCase);
                        revert ExpectedDifferentFailureReasonString(
                            err,
                            string(expectedError)
                        );
                    }
                } catch (bytes memory err) {
                    if (Utils.neq(err, expectedError)) {
                        _logRegisterPoolIdTestCase(testCase);
                        revert ExpectedDifferentFailureReason(
                            err,
                            expectedError
                        );
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
                } catch (bytes memory err) {
                    _logRegisterPoolIdTestCase(testCase);
                    revert ExpectedPassingTestFails(err);
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
            _validateTestCaseLength(rawTestCases[i], 9);
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

    function _logRegisterPoolIdTestCase(RegisterPoolIdTestCase memory testCase)
        internal
        view
    {
        console2.log("    Pool.registerPoolId");
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
            Utils.generateTestingMatrix(inputs)
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
                    _logTradeBondsTestCase(testCase);
                    revert ExpectedFailingTestPasses(expectedError);
                } catch (bytes memory err) {
                    if (Utils.neq(err, expectedError)) {
                        _logTradeBondsTestCase(testCase);
                        revert ExpectedDifferentFailureReason(
                            err,
                            expectedError
                        );
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
                    _logTradeBondsTestCase(testCase);
                    revert ExpectedPassingTestFails(err);
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
            _validateTestCaseLength(rawTestCases[i], 9);
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

    function _logTradeBondsTestCase(TradeBondsTestCase memory testCase)
        internal
        view
    {
        console2.log("    Pool.tradeBonds");
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

    // ------------------- _buyBonds unit tests ------------------ //

    struct BuyBondsTestCase {
        uint256 amount;
        LP.Reserve reserve;
        // state
        uint256 userMintAmount;
        uint256 poolPtMintAmount;
        uint256 valuePaid;
        uint256 addedShares;
        uint256 changeInBonds;
        uint128 tradeFee;
        uint128 governanceFeePercent;
        // internal calcs derived from other inputs
        uint256 impliedInterest;
        uint256 totalFee;
        uint256 govFee;
    }

    function testBuyBonds() public {
        startHoax(user);

        uint256[][] memory inputs = new uint256[][](10);

        // amount
        inputs[0] = new uint256[](2);
        inputs[0][0] = 0;
        inputs[0][1] = 1 ether;

        // reserve.shares
        inputs[1] = new uint256[](3);
        inputs[1][0] = 0;
        inputs[1][1] = 1000 ether;
        inputs[1][2] = 5555111.9999999999 ether;

        // reserve.bonds
        inputs[2] = new uint256[](3);
        inputs[2][0] = 0;
        inputs[2][1] = 10000 ether;
        inputs[2][2] = 53333222.167777777777 ether;

        // userMintAmount
        inputs[3] = new uint256[](2);
        inputs[3][0] = 0;
        inputs[3][1] = 1 ether;

        // ptMintAmount
        inputs[4] = new uint256[](2);
        inputs[4][0] = 0;
        inputs[4][1] = 1000000000 ether;

        // valuePaid
        inputs[5] = new uint256[](3);
        inputs[5][0] = 0;
        inputs[5][1] = 1 ether;
        inputs[5][2] = 1000 ether;

        // addedShares
        inputs[6] = new uint256[](3);
        inputs[6][0] = 0;
        inputs[6][1] = 1 ether;
        inputs[6][2] = 1000 ether;

        // changeInBonds
        inputs[7] = new uint256[](4);
        inputs[7][0] = 0;
        inputs[7][1] = 1 ether;
        inputs[7][2] = 100 ether;

        // tradeFee
        inputs[8] = new uint256[](2);
        inputs[8][0] = 0.01 ether;
        inputs[8][1] = 1.01 ether;

        // governanceFeePercent
        inputs[9] = new uint256[](2);
        inputs[9][0] = 0.01 ether;
        inputs[9][1] = 1.01 ether;

        BuyBondsTestCase[] memory testCases = _convertBuyBondsTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        for (uint256 i = 0; i < testCases.length; i++) {
            BuyBondsTestCase memory testCase = testCases[i];
            _setupBuyBondsTestCase(testCase);
            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedBuyBondsError(testCase);

            if (testCaseIsError) {
                try
                    pool.buyBondsExternal(
                        TERM_END,
                        testCase.amount,
                        testCase.reserve,
                        user
                    )
                {
                    _logBuyBondsTestCase(testCase);
                    revert ExpectedFailingTestPasses(expectedError);
                } catch Error(string memory err) {
                    if (Utils.neq(bytes(err), expectedError)) {
                        _logBuyBondsTestCase(testCase);
                        revert ExpectedDifferentFailureReasonString(
                            err,
                            string(expectedError)
                        );
                    }
                } catch (bytes memory err) {
                    if (Utils.neq(err, expectedError)) {
                        _logBuyBondsTestCase(testCase);
                        revert ExpectedDifferentFailureReason(
                            err,
                            expectedError
                        );
                    }
                }
            } else {
                uint256 userUnderlyingBalanceBefore = underlying.balanceOf(
                    address(user)
                );

                uint256 poolPtBalanceBefore = term.balanceOf(
                    TERM_END,
                    address(pool)
                );

                _registerExpectedBuyBondsEvents(testCase);
                try
                    pool.buyBondsExternal(
                        TERM_END,
                        testCase.amount,
                        testCase.reserve,
                        user
                    )
                returns (
                    uint256 newShareReserve,
                    uint256 newBondReserve,
                    uint256 bondsAmount
                ) {
                    _validateBuyBondsSuccess(
                        testCase,
                        newShareReserve,
                        newBondReserve,
                        bondsAmount,
                        userUnderlyingBalanceBefore,
                        poolPtBalanceBefore
                    );
                } catch (bytes memory err) {
                    _logBuyBondsTestCase(testCase);
                    revert ExpectedPassingTestFails(err);
                }
            }
        }
        console.log("###    %s combinations passing    ###", testCases.length);
    }

    function _validateBuyBondsSuccess(
        BuyBondsTestCase memory testCase,
        uint256 newShareReserve,
        uint256 newBondReserve,
        uint256 bondsAmount,
        uint256 userUnderlyingBalanceBefore,
        uint256 poolPtBalanceBefore
    ) internal {
        uint256 computedNewShareReserve = testCase.reserve.shares +
            testCase.addedShares;
        if (computedNewShareReserve != newShareReserve) {
            _logBuyBondsTestCase(testCase);
            assertEq(computedNewShareReserve, newShareReserve);
        }

        uint256 computedNewBondReserve = (testCase.reserve.bonds -
            testCase.changeInBonds) + (testCase.totalFee - testCase.govFee);

        if (computedNewBondReserve != newBondReserve) {
            _logBuyBondsTestCase(testCase);
            assertEq(computedNewBondReserve, newBondReserve);
        }

        uint256 computedBondsAmount = testCase.changeInBonds -
            testCase.totalFee;

        if (computedBondsAmount != bondsAmount) {
            _logBuyBondsTestCase(testCase);
            assertEq(computedBondsAmount, bondsAmount);
        }

        uint256 userUnderlyingBalanceAfter = underlying.balanceOf(user);
        uint256 poolPtBalanceAfter = term.balanceOf(TERM_END, address(pool));

        uint256 underlyingBalanceDiff = userUnderlyingBalanceBefore -
            userUnderlyingBalanceAfter;
        if (underlyingBalanceDiff != testCase.amount) {
            _logBuyBondsTestCase(testCase);
            assertEq(underlyingBalanceDiff, testCase.amount);
        }

        if (underlying.balanceOf(address(pool)) != testCase.amount) {
            _logBuyBondsTestCase(testCase);
            assertEq(underlying.balanceOf(address(pool)), testCase.amount);
        }

        uint256 poolPtBalanceDiff = poolPtBalanceBefore - poolPtBalanceAfter;
        if (poolPtBalanceDiff != bondsAmount) {
            _logBuyBondsTestCase(testCase);
            assertEq(poolPtBalanceDiff, bondsAmount);
        }

        if (term.balanceOf(TERM_END, user) != bondsAmount) {
            _logBuyBondsTestCase(testCase);
            assertEq(term.balanceOf(TERM_END, user), bondsAmount);
        }

        (, uint256 feesInBonds) = pool.governanceFees(TERM_END);

        if (feesInBonds != uint128(testCase.govFee)) {
            _logBuyBondsTestCase(testCase);
            assertEq(feesInBonds, uint128(testCase.govFee));
        }
    }

    function _convertBuyBondsTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (BuyBondsTestCase[] memory testCases)
    {
        testCases = new BuyBondsTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            _validateTestCaseLength(rawTestCases[i], 10);
            uint256 valuePaid = rawTestCases[i][5];
            uint256 changeInBonds = rawTestCases[i][7];
            uint128 tradeFee = uint128(rawTestCases[i][8]);
            uint128 governanceFeePercent = uint128(rawTestCases[i][9]);

            uint256 impliedInterest;
            uint256 totalFee;
            uint256 govFee;

            if (changeInBonds >= valuePaid) {
                impliedInterest = changeInBonds - valuePaid;
                totalFee = (impliedInterest * tradeFee) / 1e18;
                govFee = (totalFee * governanceFeePercent) / 1e18;
            }

            testCases[i] = BuyBondsTestCase({
                amount: rawTestCases[i][0],
                reserve: LP.Reserve({
                    shares: uint128(rawTestCases[i][1]),
                    bonds: uint128(rawTestCases[i][2])
                }),
                userMintAmount: rawTestCases[i][3],
                poolPtMintAmount: rawTestCases[i][4],
                valuePaid: valuePaid,
                addedShares: rawTestCases[i][6],
                changeInBonds: changeInBonds,
                tradeFee: tradeFee,
                governanceFeePercent: governanceFeePercent,
                impliedInterest: impliedInterest,
                totalFee: totalFee,
                govFee: govFee
            });
        }
    }

    function _getExpectedBuyBondsError(BuyBondsTestCase memory testCase)
        internal
        pure
        returns (bool testCaseIsError, bytes memory reason)
    {
        if (testCase.amount > testCase.userMintAmount) {
            return (true, bytes("ERC20: insufficient-balance"));
        }

        if (testCase.addedShares == 0) {
            return (true, new bytes(0)); // assembly division
        }

        // underflow in impliedInterest calculation
        if (testCase.changeInBonds < testCase.valuePaid) {
            return (true, stdError.arithmeticError);
        }

        // underflow in bond transfer, when testCase.tradeFee > 100%
        if (testCase.changeInBonds < testCase.totalFee) {
            return (true, stdError.arithmeticError);
        }

        // underflow in MultiToken
        if (
            testCase.poolPtMintAmount <
            (testCase.changeInBonds - testCase.totalFee)
        ) {
            return (true, stdError.arithmeticError);
        }

        // underflow in newBondReserve calc
        if (testCase.reserve.bonds < testCase.changeInBonds) {
            return (true, stdError.arithmeticError);
        }

        // underflow when governanceFeePercent > 100%
        if (testCase.totalFee < testCase.govFee) {
            return (true, stdError.arithmeticError);
        }

        return (false, new bytes(0));
    }

    function _setupBuyBondsTestCase(BuyBondsTestCase memory testCase) internal {
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
            testCase.tradeFee,
            factory.ERC20LINK_HASH(),
            governance,
            address(factory)
        );

        changePrank(governance);
        pool.updateGovernanceFeePercent(testCase.governanceFeePercent);
        changePrank(user);

        underlying.approve(address(pool), type(uint256).max);
        underlying.mint(user, testCase.userMintAmount);

        if (testCase.changeInBonds >= testCase.totalFee) {
            term.mintExternal(
                TERM_END,
                address(pool),
                testCase.poolPtMintAmount
            );
        }

        term.setDepositUnlockedReturnValues(
            testCase.valuePaid,
            testCase.addedShares
        );

        pool.setTradeCalculationReturnValue(testCase.changeInBonds);
    }

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    event UpdateOracle(
        uint256 poolId,
        uint256 newShareReserve,
        uint256 newBondReserve
    );

    function _registerExpectedBuyBondsEvents(BuyBondsTestCase memory testCase)
        internal
    {
        expectStrictEmit();
        emit Transfer(user, address(pool), testCase.amount);

        expectStrictEmit();
        emit DepositUnlocked(testCase.amount, 0, 0, address(pool));

        expectStrictEmit();
        emit TransferSingle(
            address(pool),
            address(pool),
            user,
            TERM_END,
            testCase.changeInBonds - testCase.totalFee
        );

        expectStrictEmit();
        emit UpdateOracle(
            TERM_END,
            testCase.reserve.shares + testCase.addedShares,
            testCase.reserve.bonds -
                testCase.changeInBonds +
                testCase.totalFee -
                testCase.govFee
        );
    }

    function _logBuyBondsTestCase(BuyBondsTestCase memory testCase)
        internal
        view
    {
        console2.log("    Pool._buyBonds");
        console2.log("    -----------------------------------------------    ");
        console2.log("    amount                 = ", testCase.amount);
        console2.log("    reserve.shares         = ", testCase.reserve.shares);
        console2.log("    reserve.bonds          = ", testCase.reserve.bonds);
        console2.log("    userMintAmount         = ", testCase.userMintAmount);
        console2.log(
            "    ptPoolMintAmount       = ",
            testCase.poolPtMintAmount
        );
        console2.log("    valuePaid              = ", testCase.valuePaid);
        console2.log("    addedShares            = ", testCase.addedShares);
        console2.log("    changeInBonds          = ", testCase.changeInBonds);
        console2.log("    tradeFee               = ", testCase.tradeFee);
        console2.log(
            "    governanceFeePercent   = ",
            testCase.governanceFeePercent
        );
        console2.log("    impliedInterest        = ", testCase.impliedInterest);
        console2.log("    totalFee               = ", testCase.totalFee);
        console2.log("    govFee                 = ", testCase.govFee);
        console2.log("");
    }

    // ------------------- _sellBonds unit tests ------------------ //

    struct SellBondsTestCase {
        uint256 amount;
        LP.Reserve reserve;
        uint256 pricePerUnlockedShare;
        uint256 userMintAmount;
        uint256 newShareReserve;
        uint256 newBondReserve;
        uint256 outputShares;
        uint256 valueSent;
    }

    function testSellBonds() public {
        startHoax(user);

        uint256[][] memory inputs = new uint256[][](9);

        // amount
        inputs[0] = new uint256[](3);
        inputs[0][0] = 0;
        inputs[0][1] = 1 ether;
        inputs[0][2] = 1267126 ether + 1211212;

        // reserve.shares
        inputs[1] = new uint256[](3);
        inputs[1][0] = 0;
        inputs[1][1] = 1000 ether;
        inputs[1][2] = 5555111.9999999999 ether;

        // reserve.bonds
        inputs[2] = new uint256[](3);
        inputs[2][0] = 0;
        inputs[2][1] = 10000 ether;
        inputs[2][2] = 53333222.167777777777 ether;

        // pricePerUnlockedShare
        inputs[3] = new uint256[](3);
        inputs[3][0] = 0;
        inputs[3][1] = 1 ether;
        inputs[3][2] = 1.1111 ether;

        // userMintAmount
        inputs[4] = new uint256[](2);
        inputs[4][0] = 0;
        inputs[4][1] = 100000000 ether;

        // newShareReserve
        inputs[5] = new uint256[](3);
        inputs[5][0] = 0;
        inputs[5][1] = 6126 ether + 1;
        inputs[5][2] = 1212121 ether + 99999999999;

        // newBondReserve
        inputs[6] = new uint256[](3);
        inputs[6][0] = 0;
        inputs[6][1] = 5999 ether + 36e4;
        inputs[6][2] = 9997999 ether + 1;

        // outputShares
        inputs[7] = new uint256[](3);
        inputs[7][0] = 0;
        inputs[7][1] = 0.99 ether;
        inputs[7][2] = 111111111 ether;

        // valueSent
        inputs[8] = new uint256[](3);
        inputs[8][0] = 0;
        inputs[8][1] = 0.6666 ether;
        inputs[8][2] = 9878777 ether;

        SellBondsTestCase[] memory testCases = _convertSellBondsTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        for (uint256 i = 0; i < testCases.length; i++) {
            SellBondsTestCase memory testCase = testCases[i];
            _setupSellBondsTestCase(testCase);
            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedSellBondsError(testCase);

            if (testCaseIsError) {
                try
                    pool.sellBondsExternal(
                        TERM_END,
                        testCase.amount,
                        testCase.reserve,
                        user
                    )
                {
                    _logSellBondsTestCase(testCase);
                    revert ExpectedFailingTestPasses(expectedError);
                } catch Error(string memory err) {
                    if (Utils.neq(bytes(err), expectedError)) {
                        _logSellBondsTestCase(testCase);
                        revert ExpectedDifferentFailureReasonString(
                            err,
                            string(expectedError)
                        );
                    }
                } catch (bytes memory err) {
                    if (Utils.neq(err, expectedError)) {
                        _logSellBondsTestCase(testCase);
                        revert ExpectedDifferentFailureReason(
                            err,
                            expectedError
                        );
                    }
                }
            } else {
                uint256 prevUserPtBalance = term.balanceOf(TERM_END, user);
                _registerExpectedSellBondsEvents(testCase);
                try
                    pool.sellBondsExternal(
                        TERM_END,
                        testCase.amount,
                        testCase.reserve,
                        user
                    )
                returns (
                    uint256 newShareReserve,
                    uint256 newBondReserve,
                    uint256 valueSent
                ) {
                    _validateSellBondsSuccess(
                        testCase,
                        newShareReserve,
                        newBondReserve,
                        valueSent,
                        prevUserPtBalance
                    );
                } catch (bytes memory err) {
                    _logSellBondsTestCase(testCase);
                    revert ExpectedPassingTestFails(err);
                }
            }
        }
        console.log("###    %s combinations passing    ###", testCases.length);
    }

    function _validateSellBondsSuccess(
        SellBondsTestCase memory testCase,
        uint256 newShareReserve,
        uint256 newBondReserve,
        uint256 valueSent,
        uint256 prevUserPtBalance
    ) internal {
        uint256 userBalanceDiff = prevUserPtBalance -
            term.balanceOf(TERM_END, user);

        if (userBalanceDiff != testCase.amount) {
            _logSellBondsTestCase(testCase);
            assertEq(userBalanceDiff, testCase.amount);
        }

        if (newShareReserve != testCase.newShareReserve) {
            _logSellBondsTestCase(testCase);
            assertEq(newShareReserve, testCase.newShareReserve);
        }
        if (newBondReserve != testCase.newBondReserve) {
            _logSellBondsTestCase(testCase);
            assertEq(newBondReserve, testCase.newBondReserve);
        }
        if (valueSent != testCase.valueSent) {
            _logSellBondsTestCase(testCase);
            assertEq(valueSent, testCase.valueSent);
        }
    }

    function _convertSellBondsTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (SellBondsTestCase[] memory testCases)
    {
        testCases = new SellBondsTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            uint256[] memory rawTestCase = rawTestCases[i];
            _validateTestCaseLength(rawTestCase, 9);

            testCases[i] = SellBondsTestCase({
                amount: rawTestCase[0],
                reserve: LP.Reserve({
                    shares: uint128(rawTestCase[1]),
                    bonds: uint128(rawTestCase[2])
                }),
                pricePerUnlockedShare: rawTestCase[3],
                userMintAmount: rawTestCase[4],
                newShareReserve: rawTestCase[5],
                newBondReserve: rawTestCase[6],
                outputShares: rawTestCase[7],
                valueSent: rawTestCase[8]
            });
        }
    }

    function _getExpectedSellBondsError(SellBondsTestCase memory testCase)
        internal
        pure
        returns (bool testCaseIsError, bytes memory reason)
    {
        if (testCase.userMintAmount < testCase.amount) {
            return (true, stdError.arithmeticError);
        }

        return (false, new bytes(0));
    }

    function _setupSellBondsTestCase(SellBondsTestCase memory testCase)
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

        term.setApproval(TERM_END, address(pool), type(uint256).max);
        term.mintExternal(TERM_END, user, testCase.userMintAmount);

        term.setPricePerUnlockedShare(testCase.pricePerUnlockedShare);
        pool.setQuoteSaleAndFeesReturnValues(
            testCase.newShareReserve,
            testCase.newBondReserve,
            testCase.outputShares
        );
        term.setUnlockReturnValue(testCase.valueSent);
    }

    event QuoteSaleAndFees(
        uint256 poolId,
        uint256 amount,
        uint128 reserveShares,
        uint128 reserveBonds,
        uint256 pricePerShare
    );

    event Unlock(address destination, uint256 tokenId, uint256 amount);

    function _registerExpectedSellBondsEvents(SellBondsTestCase memory testCase)
        internal
    {
        expectStrictEmit();
        emit TransferSingle(
            address(pool),
            user,
            address(pool),
            TERM_END,
            testCase.amount
        );

        expectStrictEmit();
        emit QuoteSaleAndFees(
            TERM_END,
            testCase.amount,
            testCase.reserve.shares,
            testCase.reserve.bonds,
            testCase.pricePerUnlockedShare
        );

        expectStrictEmit();
        emit UpdateOracle(
            TERM_END,
            testCase.newShareReserve,
            testCase.newBondReserve
        );

        expectStrictEmit();
        emit Unlock(user, term.UNLOCKED_YT_ID(), testCase.outputShares);
    }

    function _logSellBondsTestCase(SellBondsTestCase memory testCase)
        internal
        view
    {
        console2.log("    Pool._sellBonds");
        console2.log("    -----------------------------------------------    ");
        console2.log("    amount                       = ", testCase.amount);
        console2.log(
            "    reserve.shares               = ",
            testCase.reserve.shares
        );
        console2.log(
            "    reserve.bonds                = ",
            testCase.reserve.bonds
        );
        console2.log(
            "    pricePerUnlockedShare        = ",
            testCase.pricePerUnlockedShare
        );
        console2.log(
            "    userMintAmount               = ",
            testCase.userMintAmount
        );
        console2.log(
            "    poolUnderlyingMintAmount     = ",
            testCase.userMintAmount
        );
        console2.log(
            "    newShareReserve              = ",
            testCase.newShareReserve
        );
        console2.log(
            "    newBondReserve               = ",
            testCase.newBondReserve
        );
        console2.log(
            "    outputShares                 = ",
            testCase.outputShares
        );
        console2.log("    valueSent                    = ", testCase.valueSent);
        console2.log("");
    }

    // ------------------- _quoteSaleAndFees unit tests ------------------ //

    struct QuoteSaleAndFeesTestCase {
        // args
        uint256 amount;
        LP.Reserve reserve;
        uint256 pricePerShare;
        // state
        uint256 outputShares;
        uint128 tradeFee;
        uint128 governanceFeePercent;
        // internal calcs
        uint256 shareValue;
        uint256 fee;
        uint256 shareFee;
        uint256 governanceFee;
        uint256 lpFee;
    }

    function testQuoteSaleAndFees() public {
        startHoax(user);

        uint256[][] memory inputs = new uint256[][](7);

        // amount
        inputs[0] = new uint256[](3);
        inputs[0][0] = 0;
        inputs[0][1] = 1 ether;
        inputs[0][2] = 13333 ether + 676767676767;

        // reserve.shares
        inputs[1] = new uint256[](3);
        inputs[1][0] = 0;
        inputs[1][1] = 1000 ether;
        inputs[1][2] = 5555111.9999999999 ether;

        // reserve.bonds
        inputs[2] = new uint256[](3);
        inputs[2][0] = 0;
        inputs[2][1] = 10000 ether;
        inputs[2][2] = 53333222.167777777777 ether;

        // pricePerShare
        inputs[3] = new uint256[](4);
        inputs[3][0] = 0;
        inputs[3][1] = 0.5 ether;
        inputs[3][2] = 1 ether;
        inputs[3][3] = 2 ether;

        // outputShares
        inputs[4] = new uint256[](3);
        inputs[4][0] = 0;
        inputs[4][1] = 1 ether;
        inputs[4][2] = 20000000 ether;

        // tradeFee
        inputs[5] = new uint256[](2);
        inputs[5][0] = 0.01 ether;
        inputs[5][1] = 1.01 ether;

        // governanceFeePercent
        inputs[6] = new uint256[](2);
        inputs[6][0] = 0.01 ether;
        inputs[6][1] = 1.01 ether;

        QuoteSaleAndFeesTestCase[]
            memory testCases = _convertQuoteSaleAndFeesTestCase(
                Utils.generateTestingMatrix(inputs)
            );

        for (uint256 i = 0; i < testCases.length; i++) {
            QuoteSaleAndFeesTestCase memory testCase = testCases[i];
            _setupQuoteSaleAndFeesTestCase(testCase);
            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedQuoteSaleAndFeesError(testCase);

            if (testCaseIsError) {
                try
                    pool.quoteSaleAndFeesExternal(
                        TERM_END,
                        testCase.amount,
                        testCase.reserve,
                        testCase.pricePerShare
                    )
                {
                    _logQuoteSaleAndFeesTestCase(testCase);
                    revert ExpectedFailingTestPasses(expectedError);
                } catch Error(string memory err) {
                    if (Utils.neq(bytes(err), expectedError)) {
                        _logQuoteSaleAndFeesTestCase(testCase);
                        revert ExpectedDifferentFailureReasonString(
                            err,
                            string(expectedError)
                        );
                    }
                } catch (bytes memory err) {
                    if (Utils.neq(err, expectedError)) {
                        _logQuoteSaleAndFeesTestCase(testCase);
                        revert ExpectedDifferentFailureReason(
                            err,
                            expectedError
                        );
                    }
                }
            } else {
                try
                    pool.quoteSaleAndFeesExternal(
                        TERM_END,
                        testCase.amount,
                        testCase.reserve,
                        testCase.pricePerShare
                    )
                returns (
                    uint256 newShareReserve,
                    uint256 newBondReserve,
                    uint256 valueSent
                ) {
                    _validateQuoteSaleAndFeesSuccess(
                        testCase,
                        newShareReserve,
                        newBondReserve,
                        valueSent
                    );
                } catch (bytes memory err) {
                    _logQuoteSaleAndFeesTestCase(testCase);
                    revert ExpectedPassingTestFails(err);
                }
            }
        }
        console.log("###    %s combinations passing    ###", testCases.length);
    }

    function _validateQuoteSaleAndFeesSuccess(
        QuoteSaleAndFeesTestCase memory testCase,
        uint256 newShareReserve,
        uint256 newBondReserve,
        uint256 valueSent
    ) internal {
        uint256 computedNewShareReserve = (testCase.reserve.shares -
            testCase.outputShares) + testCase.lpFee;
        if (newShareReserve != computedNewShareReserve) {
            _logQuoteSaleAndFeesTestCase(testCase);
            assertEq(newShareReserve, computedNewShareReserve);
        }

        uint256 computedNewBondReserve = testCase.reserve.bonds +
            testCase.amount;
        if (newBondReserve != computedNewBondReserve) {
            _logQuoteSaleAndFeesTestCase(testCase);
            assertEq(newBondReserve, computedNewBondReserve);
        }

        uint256 computedValueSent = testCase.outputShares - testCase.shareFee;
        if (computedValueSent != valueSent) {
            _logQuoteSaleAndFeesTestCase(testCase);
            assertEq(valueSent, computedValueSent);
        }

        (uint256 feesInShares, ) = pool.governanceFees(TERM_END);
        if (feesInShares != testCase.governanceFee) {
            _logQuoteSaleAndFeesTestCase(testCase);
            assertEq(feesInShares, testCase.governanceFee);
        }
    }

    function _convertQuoteSaleAndFeesTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (QuoteSaleAndFeesTestCase[] memory testCases)
    {
        testCases = new QuoteSaleAndFeesTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            uint256[] memory rawTestCase = rawTestCases[i];
            _validateTestCaseLength(rawTestCase, 7);

            uint256 amount = rawTestCase[0];
            uint256 pricePerShare = rawTestCase[3];
            uint256 outputShares = rawTestCase[4];
            uint128 tradeFee = uint128(rawTestCase[5]);
            uint128 governanceFeePercent = uint128(rawTestCase[6]);

            uint256 shareValue = (outputShares * pricePerShare) / 1e18;

            uint256 impliedInterest = amount >= shareValue
                ? amount - shareValue
                : 0;
            uint256 fee = (impliedInterest * uint256(tradeFee)) / 1e18;
            uint256 shareFee = pricePerShare > 0
                ? (fee * 1e18) / pricePerShare
                : 0;

            uint256 governanceFee = (shareFee * uint256(governanceFeePercent)) /
                1e18;
            uint256 lpFee = shareFee >= governanceFee
                ? shareFee - governanceFee
                : 0;

            testCases[i] = QuoteSaleAndFeesTestCase({
                amount: amount,
                reserve: LP.Reserve({
                    shares: uint128(rawTestCase[1]),
                    bonds: uint128(rawTestCase[2])
                }),
                pricePerShare: pricePerShare,
                outputShares: outputShares,
                tradeFee: tradeFee,
                governanceFeePercent: governanceFeePercent,
                shareValue: shareValue,
                fee: fee,
                shareFee: shareFee,
                governanceFee: governanceFee,
                lpFee: lpFee
            });
        }
    }

    function _getExpectedQuoteSaleAndFeesError(
        QuoteSaleAndFeesTestCase memory testCase
    ) internal pure returns (bool testCaseIsError, bytes memory reason) {
        if (testCase.shareValue > testCase.amount) {
            return (true, stdError.arithmeticError);
        }
        if (testCase.pricePerShare == 0) {
            return (true, stdError.divisionError);
        }

        if (testCase.shareFee < testCase.governanceFee) {
            return (true, stdError.arithmeticError);
        }

        if (testCase.reserve.shares < testCase.outputShares) {
            return (true, stdError.arithmeticError);
        }

        if (testCase.outputShares < testCase.shareFee) {
            return (true, stdError.arithmeticError);
        }

        return (false, new bytes(0));
    }

    function _setupQuoteSaleAndFeesTestCase(
        QuoteSaleAndFeesTestCase memory testCase
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
            testCase.tradeFee,
            factory.ERC20LINK_HASH(),
            governance,
            address(factory)
        );

        changePrank(governance);
        pool.updateGovernanceFeePercent(testCase.governanceFeePercent);
        changePrank(user);
        pool.setTradeCalculationReturnValue(testCase.outputShares);
    }

    function _logQuoteSaleAndFeesTestCase(
        QuoteSaleAndFeesTestCase memory testCase
    ) internal view {
        console2.log("    Pool._quoteSaleAndFees");
        console2.log("    -----------------------------------------------    ");
        console2.log("    amount                       = ", testCase.amount);
        console2.log(
            "    reserve.shares               = ",
            testCase.reserve.shares
        );
        console2.log(
            "    reserve.bonds                = ",
            testCase.reserve.bonds
        );
        console2.log(
            "    pricePerShare                = ",
            testCase.pricePerShare
        );
        console2.log(
            "    outputShares                 = ",
            testCase.outputShares
        );
        console2.log("    tradeFee                     = ", testCase.tradeFee);
        console2.log(
            "    governanceFeePercent         = ",
            testCase.governanceFeePercent
        );
        console2.log(
            "    shareValue                   = ",
            testCase.shareValue
        );
        console2.log("    fee                          = ", testCase.fee);
        console2.log("    shareFee                     = ", testCase.shareFee);
        console2.log(
            "    governanceFee                = ",
            testCase.governanceFee
        );
        console2.log("    lpFee                        = ", testCase.lpFee);
        console2.log("");
    }

    // ------------------- purchaseYt unit tests ------------------ //

    struct PurchaseYtTestCase {
        // args
        uint256 poolId;
        uint256 amount;
        uint256 maxInput;
        // state
        uint256 userMintAmount;
        LP.Reserve reserve;
        uint256 pricePerUnlockedShare;
        uint256 outputShares;
        uint256 pt;
        uint256 yt;
        // internal calcs
        uint256 newShareReserve;
        uint256 newBondReserve;
        uint256 underlyingOwed;
    }

    function testPurchaseYt() public {
        startHoax(user);

        uint256[][] memory inputs = new uint256[][](10);

        // poolId
        inputs[0] = new uint256[](3);
        inputs[0][0] = 0;
        inputs[0][1] = block.timestamp;
        inputs[0][2] = TERM_END;

        // amount
        inputs[1] = new uint256[](3);
        inputs[1][0] = 0;
        inputs[1][1] = 1 ether;
        inputs[1][2] = 22 ether + 376;

        // maxInput
        inputs[2] = new uint256[](2);
        inputs[2][0] = 0;
        inputs[2][1] = 1 ether; // override this case with underlyingOwed

        // userMintAmount
        inputs[3] = new uint256[](2);
        inputs[3][0] = 0;
        inputs[3][1] = 100000000000000 ether;

        // reserve.shares
        inputs[4] = new uint256[](2);
        inputs[4][0] = 0;
        inputs[4][1] = 999999999999999 ether;

        // reserve.bonds
        inputs[5] = new uint256[](2);
        inputs[5][0] = 0;
        inputs[5][1] = 10000000000000 ether;

        // pricePerUnlockedShare
        inputs[6] = new uint256[](4);
        inputs[6][0] = 0;
        inputs[6][1] = 0.9 ether;
        inputs[6][2] = 1 ether;
        inputs[6][3] = 1.2 ether;

        // outputShares
        inputs[7] = new uint256[](3);
        inputs[7][0] = 0;
        inputs[7][1] = 1 ether;
        inputs[7][2] = 22 ether + 1221e7;

        // pt
        inputs[8] = new uint256[](3);
        inputs[8][0] = 0;
        inputs[8][1] = 1 ether;
        inputs[8][2] = 22 ether + 375;

        // yt
        inputs[9] = new uint256[](3);
        inputs[9][0] = 0;
        inputs[9][1] = 1 ether;
        inputs[9][2] = 22 ether + 375;

        PurchaseYtTestCase[] memory testCases = _convertPurchaseYtTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        for (uint256 i = 0; i < testCases.length; i++) {
            PurchaseYtTestCase memory testCase = testCases[i];
            _setupPurchaseYtTestCase(testCase);
            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedPurchaseYtError(testCase);

            if (testCaseIsError) {
                try
                    pool.purchaseYt(
                        testCase.poolId,
                        testCase.amount,
                        user,
                        testCase.maxInput
                    )
                {
                    _logPurchaseYtTestCase(testCase);
                    revert ExpectedFailingTestPasses(expectedError);
                } catch Error(string memory err) {
                    if (Utils.neq(bytes(err), expectedError)) {
                        _logPurchaseYtTestCase(testCase);
                        revert ExpectedDifferentFailureReasonString(
                            err,
                            string(expectedError)
                        );
                    }
                } catch (bytes memory err) {
                    if (Utils.neq(err, expectedError)) {
                        _logPurchaseYtTestCase(testCase);
                        revert ExpectedDifferentFailureReason(
                            err,
                            expectedError
                        );
                    }
                }
            } else {
                uint256 prevUserBalance = underlying.balanceOf(user);
                uint256 prevPoolBalance = underlying.balanceOf(address(pool));
                _registerExpectedPurchaseYtEvents(testCase);
                try
                    pool.purchaseYt(
                        testCase.poolId,
                        testCase.amount,
                        user,
                        testCase.maxInput
                    )
                {
                    _validatePurchaseYtSuccess(
                        testCase,
                        prevUserBalance,
                        prevPoolBalance
                    );
                } catch (bytes memory err) {
                    _logPurchaseYtTestCase(testCase);
                    revert ExpectedPassingTestFails(err);
                }
            }
        }
        console.log("###    %s combinations passing    ###", testCases.length);
    }

    function _validatePurchaseYtSuccess(
        PurchaseYtTestCase memory testCase,
        uint256 prevUserBalance,
        uint256 prevPoolBalance
    ) internal {
        uint256 userBalanceDiff = prevUserBalance - underlying.balanceOf(user);
        if (testCase.underlyingOwed != userBalanceDiff) {
            _logPurchaseYtTestCase(testCase);
            assertEq(testCase.underlyingOwed, userBalanceDiff);
        }

        uint256 poolBalanceDiff = underlying.balanceOf(address(pool)) -
            prevPoolBalance;
        if (testCase.underlyingOwed != poolBalanceDiff) {
            _logPurchaseYtTestCase(testCase);
            assertEq(testCase.underlyingOwed, userBalanceDiff);
        }
    }

    event YtPurchased(
        uint256 indexed poolId,
        address indexed receiver,
        uint256 amountOfYtMinted,
        uint256 sharesIn
    );

    event Lock(
        uint256[] assetIds,
        uint256[] assetAmounts,
        uint256 underlyingAmount,
        bool hasPreFunding,
        address ytDestination,
        address ptDestination,
        uint256 ytBeginDate,
        uint256 expiration
    );

    function _registerExpectedPurchaseYtEvents(
        PurchaseYtTestCase memory testCase
    ) internal {
        expectStrictEmit();
        emit QuoteSaleAndFees(
            testCase.poolId,
            testCase.amount,
            testCase.reserve.shares,
            testCase.reserve.bonds,
            testCase.pricePerUnlockedShare
        );

        expectStrictEmit();
        emit Transfer(user, address(pool), testCase.underlyingOwed);

        uint256[] memory ids = new uint256[](1);
        ids[0] = term.UNLOCKED_YT_ID();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = testCase.outputShares;

        expectStrictEmit();
        emit Lock(
            ids,
            amounts,
            testCase.underlyingOwed,
            false,
            user,
            address(pool),
            block.timestamp,
            testCase.poolId
        );

        expectStrictEmit();
        emit UpdateOracle(
            testCase.poolId,
            testCase.newShareReserve,
            testCase.newBondReserve
        );

        expectStrictEmit();
        emit Update(
            testCase.poolId,
            uint128(testCase.newBondReserve),
            uint128(testCase.newShareReserve)
        );

        expectStrictEmit();
        emit YtPurchased(
            testCase.poolId,
            user,
            testCase.yt,
            testCase.underlyingOwed
        );
    }

    function _convertPurchaseYtTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (PurchaseYtTestCase[] memory testCases)
    {
        testCases = new PurchaseYtTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            uint256[] memory rawTestCase = rawTestCases[i];
            _validateTestCaseLength(rawTestCase, 10);

            uint256 amount = rawTestCase[1];
            uint256 pricePerUnlockedShare = rawTestCase[6];
            uint256 outputShares = rawTestCase[7];

            uint256 saleUnderlying = (outputShares * pricePerUnlockedShare) /
                1e18;
            uint256 underlyingOwed = amount >= saleUnderlying
                ? amount - saleUnderlying
                : 0;

            LP.Reserve memory reserve = LP.Reserve({
                shares: uint128(rawTestCase[4]),
                bonds: uint128(rawTestCase[5])
            });

            uint256 newShareReserve = reserve.shares >= outputShares
                ? reserve.shares - outputShares
                : 0;
            uint256 newBondReserve = reserve.bonds + amount;

            testCases[i] = PurchaseYtTestCase({
                poolId: rawTestCase[0],
                amount: amount,
                maxInput: rawTestCase[2] == 0 ? 0 : underlyingOwed,
                userMintAmount: rawTestCase[3],
                reserve: reserve,
                pricePerUnlockedShare: pricePerUnlockedShare,
                outputShares: rawTestCase[7],
                pt: rawTestCase[8],
                yt: rawTestCase[9],
                newShareReserve: newShareReserve,
                newBondReserve: newBondReserve,
                underlyingOwed: underlyingOwed
            });
        }
    }

    function _getExpectedPurchaseYtError(PurchaseYtTestCase memory testCase)
        internal
        view
        returns (bool testCaseIsError, bytes memory reason)
    {
        if (testCase.poolId <= block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermExpired.selector)
            );
        }

        if (testCase.reserve.shares == 0 && testCase.reserve.bonds == 0) {
            return (
                true,
                abi.encodeWithSelector(ElementError.PoolNotInitialized.selector)
            );
        }

        if (
            testCase.amount <
            ((testCase.outputShares * testCase.pricePerUnlockedShare) / 1e18)
        ) {
            return (true, stdError.arithmeticError);
        }

        if (testCase.underlyingOwed > testCase.maxInput) {
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.ExceededSlippageLimit.selector
                )
            );
        }

        if (testCase.userMintAmount < testCase.underlyingOwed) {
            return (true, bytes("ERC20: insufficient-balance"));
        }

        if (testCase.pt != testCase.amount) {
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.InaccurateUnlockShareTrade.selector
                )
            );
        }

        return (false, new bytes(0));
    }

    function _setupPurchaseYtTestCase(PurchaseYtTestCase memory testCase)
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
            testCase.reserve.shares,
            testCase.reserve.bonds
        );

        term.setPricePerUnlockedShare(testCase.pricePerUnlockedShare);
        pool.setQuoteSaleAndFeesReturnValues(
            testCase.newShareReserve,
            testCase.newBondReserve,
            testCase.outputShares
        );
        underlying.approve(address(pool), type(uint256).max);
        underlying.mint(user, testCase.userMintAmount);
        term.setLockValues(testCase.pt, testCase.yt);
    }

    function _logPurchaseYtTestCase(PurchaseYtTestCase memory testCase)
        internal
        view
    {
        console2.log("    Pool.purchaseYt");
        console2.log("    -----------------------------------------------    ");
        console2.log("    poolId                       = ", testCase.poolId);
        console2.log("    amount                       = ", testCase.amount);
        console2.log("    maxInput                     = ", testCase.maxInput);
        console2.log(
            "    userMintAmount               = ",
            testCase.userMintAmount
        );
        console2.log(
            "    reserve.shares               = ",
            testCase.reserve.shares
        );
        console2.log(
            "    reserve.bonds                = ",
            testCase.reserve.bonds
        );
        console2.log(
            "    pricePerUnlockedShare        = ",
            testCase.pricePerUnlockedShare
        );
        console2.log(
            "    outputShares                 = ",
            testCase.outputShares
        );
        console2.log("    pt                           = ", testCase.pt);
        console2.log("    yt                           = ", testCase.yt);
        console2.log(
            "    newShareReserve              = ",
            testCase.newShareReserve
        );
        console2.log(
            "    newBondReserve               = ",
            testCase.newBondReserve
        );
        console2.log(
            "    underlyingOwed               = ",
            testCase.underlyingOwed
        );
    }
}
