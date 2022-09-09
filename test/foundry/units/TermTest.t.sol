// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/mocks/MockTerm.sol";
import "contracts/mocks/MockERC20Permit.sol";

contract TermTest is Test {
    address public user = vm.addr(0xDEAD_BEEF);

    ForwarderFactory _factory;
    MockTerm _term;
    MockERC20Permit _underlying;

    function setUp() public {
        // Set up the required Element contracts.
        _factory = new ForwarderFactory();
        _underlying = new MockERC20Permit("Test", "TEST", 18);
        // FIXME: Consider making a user to be the owner.
        _term = new MockTerm(
            _factory.ERC20LINK_HASH(),
            address(_factory),
            IERC20(_underlying),
            address(this)
        );
    }

    // -------------------  _releasePT unit tests   ------------------ //

    // FIXME: Add documentation to this structure and the test suite at large.
    struct ReleasePTTestCase {
        uint256 amount;
        uint128 interest;
        uint256 sharesPerExpiry;
        uint256 totalSupply;
        uint256 underlying;
        uint256 userBalance;
    }

    function getExpectedErrorReleasePT(ReleasePTTestCase memory testCase)
        internal
        pure
        returns (bytes memory)
    {
        if (testCase.underlying == 0) {
            return stdError.divisionError;
        } else if (testCase.interest != 0 && testCase.sharesPerExpiry == 0) {
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

    function validateReleasePTSuccess(
        ReleasePTTestCase memory testCase,
        uint256 assetId,
        uint256 shares,
        uint256 value
    ) internal {
        // Ensure that the calculated shares and value are correct.
        uint256 expectedPTShares = testCase.sharesPerExpiry -
            (testCase.interest * 1e18) /
            testCase.underlying;
        uint256 expectedShares = (expectedPTShares * testCase.amount) /
            testCase.totalSupply;
        uint256 expectedValue = (expectedShares * testCase.underlying) / 1e18;
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

    function testCombinatorialReleasePT() public {
        // Get the test cases.
        string memory path = "./testdata/_releasePT.json";
        string memory json = vm.readFile(path);
        bytes memory rawTestCases = vm.parseJson(json);
        ReleasePTTestCase[] memory testCases = abi.decode(
            rawTestCases,
            (ReleasePTTestCase[])
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
            _term.setUnderlyingReturnValue(testCases[i].underlying);
            _term.setUserBalance(assetId, user, testCases[i].userBalance);
            _term.setTotalSupply(assetId, testCases[i].totalSupply);

            bytes memory expectedError = getExpectedErrorReleasePT(
                testCases[i]
            );
            if (expectedError.length > 0) {
                console.log("failure test case ");
                console.log("");
                console.log("    amount          = ", testCases[i].amount);
                console.log("    interest        = ", testCases[i].interest);
                console.log(
                    "    sharesPerExpiry = ",
                    testCases[i].sharesPerExpiry
                );
                console.log("    totalSupply     = ", testCases[i].totalSupply);
                console.log("    underlying      = ", testCases[i].underlying);
                console.log("    userBalance     = ", testCases[i].userBalance);
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
                console.log("    amount          = ", testCases[i].amount);
                console.log("    interest        = ", testCases[i].interest);
                console.log(
                    "    sharesPerExpiry = ",
                    testCases[i].sharesPerExpiry
                );
                console.log("    totalSupply     = ", testCases[i].totalSupply);
                console.log("    underlying      = ", testCases[i].underlying);
                console.log("    userBalance     = ", testCases[i].userBalance);
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
