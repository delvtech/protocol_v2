// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/mocks/MockLP.sol";
import "contracts/mocks/MockTerm.sol";
import "contracts/mocks/MockERC20Permit.sol";

import { ElementTest } from "test/ElementTest.sol";
import { Utils } from "test/Utils.sol";

contract LPTest is ElementTest {
    address public user = vm.addr(0xDEAD_BEEF);

    ForwarderFactory public factory;
    MockTerm public term;
    MockERC20Permit public token;
    MockLP public lp;

    function setUp() public {
        // Set up the required Element contracts.
        factory = new ForwarderFactory();
        token = new MockERC20Permit("Test", "TEST", 18);
        term = new MockTerm(
            factory.ERC20LINK_HASH(),
            address(factory),
            IERC20(token),
            address(this)
        );
        lp = new MockLP(
            token,
            term,
            factory.ERC20LINK_HASH(),
            address(factory)
        );
    }

    // -------------------  rollover unit tests   ------------------ //

    // quick sanity test.  if the user has all the lp shares, they should pull out all the reserves.
    function test_rollover() public {
        uint256 fromPoolId = 0;
        uint256 toPoolId = 12345678;
        uint256 amount = 1 ether;
        address destination = address(user);
        uint256 minOutput = 1 ether;

        lp.setDepositFromSharesReturnValue(1 ether);

        // Set the address.
        startHoax(user);

        uint256 newLpTokens = lp.rollover(
            fromPoolId,
            toPoolId,
            amount,
            destination,
            minOutput
        );

        assertEq(newLpTokens, 1 ether);
    }

    function test_rolloverCombinatorial() public {
        uint256[][] memory inputs = new uint256[][](6);
        // fromPoolId
        vm.warp(1);
        inputs[0] = new uint256[](2);
        inputs[0][0] = 0; // active
        inputs[0][1] = 12345678; // expired

        // toPoolId
        inputs[1] = new uint256[](2);
        inputs[1][0] = 0; // active
        inputs[1][1] = 12345678; // expired

        // amount
        inputs[2] = new uint256[](3);
        inputs[2][0] = 0 ether;
        inputs[2][1] = 1 ether;
        inputs[2][2] = 10_000 ether;

        // minOutput
        inputs[3] = new uint256[](3);
        inputs[3][0] = 0 ether;
        inputs[3][1] = 1 ether;
        inputs[3][2] = 10_000 ether;

        // newLpToken
        inputs[4] = new uint256[](3);
        inputs[4][0] = 0;
        inputs[4][1] = 1 ether;
        inputs[4][2] = 10_000 ether;

        RolloverTestCase[] memory testCases = _convertToRolloverTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        // Set the address.
        startHoax(user);

        for (uint256 i = 0; i < testCases.length; i++) {
            RolloverTestCase memory testCase = testCases[i];

            // ----- setup ----- //
            lp.setDepositFromSharesReturnValue(testCase.newLpToken);
            // these values don't affect anything, just set to 1
            lp.setWithdrawToSharesReturnValues(1, 1);
            // ----------------- //

            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedRolloverError(testCase);

            // if there is an expected error, try to catch it
            if (testCaseIsError) {
                _validateRolloverTestCaseError(testCase, expectedError);
                // otherwise validate the test passes
            } else {
                _validateRolloverTestCase(testCase);
            }
        }
    }

    struct RolloverTestCase {
        // pool to grab shares from
        uint256 fromPoolId;
        // pool to add shares to
        uint256 toPoolId;
        // slippage tolerange for amount of shares to rollover
        uint256 minAmountOut;
        // amount of shares to rollover
        uint256 newLpToken;
    }

    function _convertToRolloverTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (RolloverTestCase[] memory testCases)
    {
        testCases = new RolloverTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 4,
                "Raw test case must have length of 4."
            );
            testCases[i] = RolloverTestCase({
                fromPoolId: rawTestCases[i][0],
                toPoolId: rawTestCases[i][1],
                minAmountOut: rawTestCases[i][3],
                newLpToken: rawTestCases[i][4]
            });
        }
    }

    function _getExpectedRolloverError(RolloverTestCase memory testCase)
        internal
        view
        returns (bool testCaseIsError, bytes memory reason)
    {
        if (testCase.fromPoolId >= block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermNotExpired.selector)
            );
        }

        if (testCase.toPoolId < block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermExpired.selector)
            );
        }

        if (testCase.newLpToken < testCase.minAmountOut) {
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.ExceededSlippageLimit.selector
                )
            );
        }
    }

    function _validateRolloverTestCaseError(
        RolloverTestCase memory testCase,
        bytes memory expectedError
    ) internal {
        try
            lp.rollover(
                testCase.fromPoolId,
                testCase.toPoolId,
                1 ether, // amount
                address(user),
                testCase.minAmountOut
            )
        {
            _logRolloverTestCase(testCase);
            revert ExpectedFailingTestPasses(expectedError);
        } catch (bytes memory err) {
            if (Utils.neq(err, expectedError)) {
                _logRolloverTestCase(testCase);
                revert ExpectedDifferentFailureReason(err, expectedError);
            }
        }
    }

    function _validateRolloverTestCase(RolloverTestCase memory testCase)
        internal
    {
        _registerExpectedRolloverEvents(testCase);
        uint256 newLpTokens = lp.rollover(
            testCase.fromPoolId,
            testCase.toPoolId,
            1 ether, // amount,
            address(user),
            testCase.minAmountOut
        );

        bytes memory emptyError;

        uint256 expectedNewLpTokens = testCase.newLpToken;
        if (newLpTokens != expectedNewLpTokens) {
            assertEq(
                newLpTokens,
                expectedNewLpTokens,
                "unexpected new lp tokens"
            );
            _logRolloverTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }
    }

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    event WithdrawToShares(uint256 poolId, uint256 amount, address source);
    event DepositFromShares(
        uint256 poolId,
        uint256 currentShares,
        uint256 currentBonds,
        uint256 depositedShares,
        uint256 pricePerShare,
        address to
    );

    function _registerExpectedRolloverEvents(RolloverTestCase memory testCase)
        internal
    {
        if (
            testCase.fromPoolId < block.timestamp &&
            testCase.toPoolId >= block.timestamp
        ) {
            expectStrictEmit();
            emit WithdrawToShares(
                testCase.fromPoolId,
                1 ether, // amount
                address(user) // source
            );

            expectStrictEmit();
            emit DepositFromShares(
                testCase.toPoolId,
                0, // reserve shares
                0, // reserve bonds
                1, // userShares
                0, // pricePerShare
                address(user) // to
            );
        }
    }

    function _logRolloverTestCase(RolloverTestCase memory testCase)
        internal
        view
    {
        console2.log("    LP.rollover Test #%s :: %s");
        console2.log("    -----------------------------------------------    ");
        console2.log("    fromPoolId           = ", testCase.fromPoolId);
        console2.log("    toPoolId             = ", testCase.toPoolId);
        console2.log("    minAmountOut         = ", testCase.minAmountOut);
        console2.log("    newLpToken           = ", testCase.newLpToken);
        console2.log("");
    }
}
