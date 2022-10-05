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
    error ExpectedSharesNotEqual(uint256 value, uint256 expected);
    error ExpectedBondsNotEqual(uint256 value, uint256 expected);
    error ExpectedLpTokensNotEqual(uint256 value, uint256 expected);

    uint256 internal constant _UNLOCKED_TERM_ID = 1 << 255;
    address public user = makeAddress("User");

    event DepositUnlocked(
        uint256 underlyingAmount,
        uint256 ptAmount,
        uint256 ptExpiry,
        address destination
    );

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

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

    // -------------------  depositUnderlying unit tests   ------------------ //
    event Transfer(address indexed from, address indexed to, uint256 value);
    event DepositFromShares(
        uint256 poolId,
        uint256 currentShares,
        uint256 currentBonds,
        uint256 depositedShares,
        uint256 pricePerShare,
        address to
    );

    // quick sanity test.  deposit all the users bonds and shares into the pool
    function test_depositUnderlying() public {
        uint256 poolId = 12345678; // active
        uint256 amount = 1 ether;
        address destination = address(user);
        uint256 minOutput = 1 ether;
        uint256 sharesCreated = 1 ether;
        uint256 lpTokensCreated = 1 ether;

        // Set the address.
        startHoax(user);

        // setup
        term.setApprovalForAll(address(lp), true);
        token.setBalance(address(user), amount); // give user tokens
        token.approve(address(lp), type(uint256).max);

        term.setDepositUnlockedReturnValues(amount, sharesCreated);
        lp.setDepositFromSharesReturnValue(lpTokensCreated);

        expectStrictEmit();
        // transfer tokens to pool
        emit Transfer(
            address(user), // from
            address(lp), // to
            amount // amount
        );

        expectStrictEmit();
        emit DepositUnlocked(
            amount, //underlyingAmount
            0, // ptAmount
            0, // ptExpiry
            address(lp) //destination
        );

        expectStrictEmit();
        emit DepositFromShares(
            poolId, // poolId
            0, // currentShares
            0, // currentBonds
            sharesCreated, // depositedShares
            1 ether, // pricePerShare
            address(user) // to
        );

        uint256 newLpTokens = lp.depositUnderlying(
            amount,
            poolId,
            destination,
            minOutput
        );

        assertEq(newLpTokens, lpTokensCreated);
    }

    function test_depositUnderlyingCombinatorial() public {
        uint256[][] memory inputs = new uint256[][](6);
        // poolId
        vm.warp(1);
        inputs[0] = new uint256[](2);
        inputs[0][0] = 0; // active
        inputs[0][1] = 12345678; // expired

        // sharesCreated
        inputs[2] = new uint256[](2);
        inputs[2][0] = 0 ether;
        inputs[2][1] = 1 ether + 305566;

        // newLpToken
        inputs[3] = new uint256[](2);
        inputs[3][0] = 0 ether;
        inputs[3][1] = 1 ether + 34447;

        // minLpOut
        inputs[4] = new uint256[](2);
        inputs[4][0] = 0;
        inputs[4][1] = 1 ether + 329022;

        DepositUnderlyingTestCase[]
            memory testCases = _convertToDepositUnderlyingTestCase(
                Utils.generateTestingMatrix(inputs)
            );

        // Set the address.
        startHoax(user);

        for (uint256 i = 0; i < testCases.length; i++) {
            DepositUnderlyingTestCase memory testCase = testCases[i];

            _depositUnderlyingSetup(testCase);

            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedDepositUnderlyingError(testCase);

            // if there is an expected error, try to catch it
            if (testCaseIsError) {
                _validateDepositUnderlyingTestCaseError(
                    testCase,
                    expectedError
                );
                // otherwise validate the test passes
            } else {
                _validateDepositUnderlyingTestCase(testCase);
            }
        }
    }

    struct DepositUnderlyingTestCase {
        // pool to deposit bonds to
        uint256 poolId;
        // the number shares created from underlying
        uint256 sharesCreated;
        // number of lp tokens created
        uint256 newLpToken;
        // slippage tolerance for number of lp tokens to create
        uint256 minLpOut;
    }

    function _convertToDepositUnderlyingTestCase(
        uint256[][] memory rawTestCases
    ) internal pure returns (DepositUnderlyingTestCase[] memory testCases) {
        testCases = new DepositUnderlyingTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            _validateTestCaseLength(rawTestCases[i], 4);
            testCases[i] = DepositUnderlyingTestCase({
                poolId: rawTestCases[i][0],
                sharesCreated: rawTestCases[i][1],
                newLpToken: rawTestCases[i][2],
                minLpOut: rawTestCases[i][3]
            });
        }
    }

    function _depositUnderlyingSetup(DepositUnderlyingTestCase memory testCase)
        internal
    {
        // this doesn't affect in values, just set to 1 ether
        uint256 amount = 1 ether;
        // setup
        term.setApprovalForAll(address(lp), true);
        token.setBalance(address(user), amount); // give user tokens
        token.approve(address(lp), type(uint256).max);

        term.setDepositUnlockedReturnValues(amount, testCase.sharesCreated);
        lp.setDepositFromSharesReturnValue(testCase.newLpToken);
    }

    function _getExpectedDepositUnderlyingError(
        DepositUnderlyingTestCase memory testCase
    ) internal view returns (bool testCaseIsError, bytes memory reason) {
        // No minting after expiration
        if (testCase.poolId <= block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermExpired.selector)
            );
        }

        if (testCase.sharesCreated == 0) {
            return (true, stdError.divisionError);
        }

        // Check enough has been made and return that amount
        if (testCase.newLpToken < testCase.minLpOut) {
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.ExceededSlippageLimit.selector
                )
            );
        }
    }

    function _validateDepositUnderlyingTestCaseError(
        DepositUnderlyingTestCase memory testCase,
        bytes memory expectedError
    ) internal {
        try
            lp.depositUnderlying(
                1 ether,
                testCase.poolId,
                address(user),
                testCase.minLpOut
            )
        {
            _logDepositUnderlyingTestCase(testCase);
            revert ExpectedFailingTestPasses(expectedError);
        } catch (bytes memory err) {
            if (Utils.neq(err, expectedError)) {
                _logDepositUnderlyingTestCase(testCase);
                revert ExpectedDifferentFailureReason(err, expectedError);
            }
        }
    }

    function _validateDepositUnderlyingTestCase(
        DepositUnderlyingTestCase memory testCase
    ) internal {
        _registerExpectedDepositUnderlyingEvents(testCase);
        uint256 amount = 1 ether;
        uint256 lpCreated = lp.depositUnderlying(
            amount,
            testCase.poolId,
            address(user),
            testCase.minLpOut
        );

        bytes memory emptyError = new bytes(0);

        if (lpCreated != testCase.newLpToken) {
            assertEq(
                lpCreated,
                testCase.newLpToken,
                "unexpected lp tokens created"
            );
            _logDepositUnderlyingTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }
    }

    function _registerExpectedDepositUnderlyingEvents(
        DepositUnderlyingTestCase memory testCase
    ) internal {
        uint256 amount = 1 ether;
        if (testCase.poolId > block.timestamp) {
            expectStrictEmit();
            // transfer tokens to pool
            emit Transfer(
                address(user), // from
                address(lp), // to
                amount // amount
            );

            expectStrictEmit();
            emit DepositUnlocked(
                amount, //underlyingAmount
                0, // ptAmount
                0, // ptExpiry
                address(lp) //destination
            );

            if (testCase.sharesCreated > 0) {
                uint256 pricePerShare = (amount * 1 ether) /
                    testCase.sharesCreated;
                expectStrictEmit();
                emit DepositFromShares(
                    testCase.poolId, // poolId
                    0, // currentShares
                    0, // currentBonds
                    testCase.sharesCreated, // depositedShares
                    pricePerShare, // pricePerShare
                    address(user) // to
                );
            }
        }
    }

    function _logDepositUnderlyingTestCase(
        DepositUnderlyingTestCase memory testCase
    ) internal view {
        console2.log("    LP.depositUnderlying Test #%s :: %s");
        console2.log("    -----------------------------------------------    ");
        console2.log("    poolId = ", testCase.poolId);
        console2.log("    sharesCreated = ", testCase.sharesCreated);
        console2.log("    newLpToken= ", testCase.newLpToken);
        console2.log("    minLpOut = ", testCase.minLpOut);
        console2.log("");
    }
}
