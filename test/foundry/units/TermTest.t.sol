// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/mocks/MockTerm.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "../Utils.sol";

contract TermTest is Test {
    address public user = vm.addr(0xDEAD_BEEF);

    ForwarderFactory _factory;
    MockTerm _term;
    MockERC20Permit _underlying;

    function setUp() public {
        // Set up the required Element contracts.
        _factory = new ForwarderFactory();
        _underlying = new MockERC20Permit("Test", "TEST", 18);
        _term = new MockTerm(
            _factory.ERC20LINK_HASH(),
            address(_factory),
            IERC20(_underlying),
            address(this)
        );
    }

    // FIXME: Remove this.

    function testGenerateTestMatrix() public {
        uint256[] memory inputs = new uint256[](3);
        inputs[0] = 0;
        inputs[1] = 1;
        inputs[2] = 2;
        uint256[][] memory testMatrix = Utils.generateTestingMatrix(4, inputs);

        console.log("[");
        for (uint256 i = 0; i < testMatrix.length; i++) {
            console.log("    ", testMatrix[i][1]);
        }
        console.log("]");
    }

    // -------------------  _releasePT unit tests   ------------------ //

    function testCombinatorialReleasePT() public {
        // Get the test cases.
        uint256[] memory inputs = new uint256[](4);
        inputs[0] = 0;
        inputs[1] = 1 ether;
        inputs[2] = 2 ether;
        inputs[3] = 3.7435 ether;
        ReleasePTTestCase[] memory testCases = convertToReleasePTTestCase(
            Utils.generateTestingMatrix(6, inputs)
        );

        // Set the address.
        startHoax(user);

        // Create an asset ID of a PT that expires at 10,000.
        uint256 assetId = encodeAssetId(false, 0, 10_000);

        for (uint256 i = 0; i < testCases.length; i++) {
            // Set up the test's state in the term contract.
            Term.FinalizedState memory finalState = Term.FinalizedState({
                pricePerShare: 0.1 ether,
                interest: testCases[i].interest
            });
            _term.setSharesPerExpiry(assetId, testCases[i].sharesPerExpiry);
            _term.setUnderlyingReturnValue(testCases[i].currentPricePerShare);
            _term.setUserBalance(assetId, user, testCases[i].userBalance);
            _term.setTotalSupply(assetId, testCases[i].totalSupply);

            bytes memory expectedError = getExpectedErrorReleasePT(
                testCases[i]
            );
            if (expectedError.length > 0) {
                console.log("failure test case ");
                console.log("");
                console.log("    amount               = ", testCases[i].amount);
                console.log(
                    "    interest             = ",
                    testCases[i].interest
                );
                console.log(
                    "    sharesPerExpiry      = ",
                    testCases[i].sharesPerExpiry
                );
                console.log(
                    "    totalSupply          = ",
                    testCases[i].totalSupply
                );
                console.log(
                    "    currentPricePerShare = ",
                    testCases[i].currentPricePerShare
                );
                console.log(
                    "    userBalance          = ",
                    testCases[i].userBalance
                );
                console.log("");

                vm.expectRevert(expectedError);
                _term.releasePTExternal(
                    finalState,
                    assetId,
                    user,
                    testCases[i].amount
                );
            } else {
                console.log("success test case ");
                console.log("");
                console.log("    amount               = ", testCases[i].amount);
                console.log(
                    "    interest             = ",
                    testCases[i].interest
                );
                console.log(
                    "    sharesPerExpiry      = ",
                    testCases[i].sharesPerExpiry
                );
                console.log(
                    "    totalSupply          = ",
                    testCases[i].totalSupply
                );
                console.log(
                    "    currentPricePerShare = ",
                    testCases[i].currentPricePerShare
                );
                console.log(
                    "    userBalance          = ",
                    testCases[i].userBalance
                );
                console.log("");

                (uint256 shares, uint256 value) = _term.releasePTExternal(
                    finalState,
                    assetId,
                    user,
                    testCases[i].amount
                );
                validateReleasePTSuccess(testCases[i], assetId, shares, value);
            }
        }
    }

    struct ReleasePTTestCase {
        // The amount of PT to release.
        uint256 amount;
        // The current price of a single share in the term.
        uint256 currentPricePerShare;
        // TODO: Make sure we test that all of the interest is consumed by
        //       withdrawals of the total supply of YT and PT.
        //
        // The amount of underlying backing the PT and YT after finalization.
        uint128 interest;
        // The amount of shares outstanding for the term.
        uint256 sharesPerExpiry;
        // The total supply of PT.
        uint256 totalSupply;
        // The user's balance of PT.
        uint256 userBalance;
    }

    // Converts a raw testing matrix to a structured array.
    function convertToReleasePTTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (ReleasePTTestCase[] memory testCases)
    {
        testCases = new ReleasePTTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 6,
                "Raw test case must have length of 6."
            );
            testCases[i] = ReleasePTTestCase({
                amount: rawTestCases[i][0],
                interest: uint128(rawTestCases[i][1]),
                currentPricePerShare: rawTestCases[i][2],
                sharesPerExpiry: rawTestCases[i][3],
                totalSupply: rawTestCases[i][4],
                userBalance: rawTestCases[i][5]
            });
        }
    }

    // Given a test case, get the expected error that will be thrown by a failed
    // call to _releasePT.
    function getExpectedErrorReleasePT(ReleasePTTestCase memory testCase)
        internal
        pure
        returns (bytes memory)
    {
        if (testCase.currentPricePerShare == 0) {
            return stdError.divisionError;
        } else if (
            (testCase.interest * 1e18) / testCase.currentPricePerShare >
            testCase.sharesPerExpiry
        ) {
            // TODO: Re-evaluate this case in the context of _releaseYT.
            return stdError.arithmeticError;
        } else if (testCase.totalSupply == 0) {
            return stdError.divisionError;
        } else if (
            testCase.amount > testCase.userBalance ||
            testCase.amount > testCase.totalSupply
        ) {
            return stdError.arithmeticError;
        }
        return new bytes(0);
    }

    // Given a test case, validate the state transitions and return values of a
    // successful call to _releasePT.
    function validateReleasePTSuccess(
        ReleasePTTestCase memory testCase,
        uint256 assetId,
        uint256 shares,
        uint256 value
    ) internal {
        // Ensure that the calculated shares and value are correct.
        uint256 expectedPTShares = testCase.sharesPerExpiry -
            (testCase.interest * 1e18) /
            testCase.currentPricePerShare;
        uint256 expectedShares = (expectedPTShares * testCase.amount) /
            testCase.totalSupply;
        uint256 expectedValue = (expectedShares *
            testCase.currentPricePerShare) / 1e18;
        assertEq(shares, expectedShares);
        assertEq(value, expectedValue);

        // Ensure that the state was updated correctly.
        assertEq(
            _term.totalSupply(assetId),
            testCase.totalSupply - testCase.amount
        );
        assertEq(
            _term.balanceOf(assetId, user),
            testCase.userBalance - testCase.amount
        );
        assertEq(
            _term.sharesPerExpiry(assetId),
            testCase.sharesPerExpiry - expectedShares
        );
    }

    // ------------------- _parseAssetId unit tests ------------------ //

    function encodeAssetId(
        bool isYieldToken,
        uint256 startDate,
        uint256 expirationDate
    ) internal pure returns (uint256) {
        return
            (uint256(isYieldToken ? 1 : 0) << 255) |
            (startDate << 128) |
            expirationDate;
    }

    function testParseAssetId__principalTokenId() public {
        bool[4] memory isYieldTokenInputs = [false, false, false, false];
        uint256[4] memory startDateInputs = [uint256(0), 0, 15, 43];
        uint256[4] memory expirationDateInputs = [uint256(0), 12, 0, 67];

        for (uint256 i = 0; i < isYieldTokenInputs.length; i++) {
            (
                bool isYieldToken,
                uint256 startDate,
                uint256 expirationDate
            ) = _term.parseAssetIdExternal(
                    encodeAssetId(
                        isYieldTokenInputs[i],
                        startDateInputs[i],
                        expirationDateInputs[i]
                    )
                );

            assertEq(isYieldToken, false);
            assertEq(startDate, 0);
            // TODO: Adding the edge case of there being a start date to the
            // test as a sanity check.
            assertEq(
                expirationDate,
                (startDateInputs[i] << 128) | expirationDateInputs[i]
            );
        }
    }

    function testParseAssetId__yieldTokenId() public {
        bool[4] memory isYieldTokenInputs = [true, true, true, true];
        uint256[4] memory startDateInputs = [uint256(0), 0, 15, 43];
        uint256[4] memory expirationDateInputs = [uint256(0), 12, 0, 67];

        for (uint256 i = 0; i < isYieldTokenInputs.length; i++) {
            (
                bool isYieldToken,
                uint256 startDate,
                uint256 expirationDate
            ) = _term.parseAssetIdExternal(
                    encodeAssetId(
                        isYieldTokenInputs[i],
                        startDateInputs[i],
                        expirationDateInputs[i]
                    )
                );

            assertEq(isYieldToken, true);
            assertEq(startDate, startDateInputs[i]);
            assertEq(expirationDate, expirationDateInputs[i]);
        }
    }
}
