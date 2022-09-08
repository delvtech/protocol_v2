// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";
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

    // FIXME: Here are the pieces of state that we need to test with.
    //
    // 1. [ ] shares
    // 2. [ ] underlying
    // 3. [ ] interest
    // 4. [ ] total supply
    // 5. [ ] user balance
    //
    // We should test the full range with both zero and non-zero inputs.
    //
    // I should write a table driven test suite that can evaluate all of these
    // possibilities for failures and successes.

    // FIXME: Write the success tests.
    //
    // function testReleasePT() public {
    //     startHoax(user);

    //     // Create an asset ID of a PT that expires at 10,000.
    //     uint256 assetId = encodeAssetId(false, 0, 10_000);

    //     // Set up the test's state in the term contract.
    //     Term.FinalizedState memory finalState = Term.FinalizedState ({
    //         pricePerShare: 0.1 ether,
    //         interest: 0
    //     });
    //     _term.setSharesPerExpiry(assetId, 0);
    //     _term.setUnderlyingReturnValue(0);
    //     _term.setUserBalance(assetId, user, 0);
    //     _term.setTotalSupply(assetId, 0);

    //     // Expect a division by zero error.
    //     vm.expectRevert(stdError.divisionError);

    //     // Attempt to release the PT.
    //     _term.releasePTExternal(
    //         finalState,
    //         assetId,
    //         user,
    //         1 ether
    //     );
    // }

    struct FailureTestCaseReleasePT {
        uint256 amount;
        uint128 interest;
        uint256 sharesPerExpiry;
        uint256 underlying;
        uint256 userBalance;
        uint256 totalSupply;
        bytes expectedError;
    }

    function executeReleasePTFailureTestCases(
        FailureTestCaseReleasePT[] memory _testCases
    ) internal {
        startHoax(user);

        // Create an asset ID of a PT that expires at 10,000.
        uint256 assetId = encodeAssetId(false, 0, 10_000);

        for (uint256 i = 0; i < _testCases.length; i++) {
            console.log("test case ", i);

            // Set up the test's state in the term contract.
            Term.FinalizedState memory finalState = Term.FinalizedState({
                pricePerShare: 0.1 ether,
                interest: _testCases[i].interest
            });
            _term.setSharesPerExpiry(assetId, _testCases[i].sharesPerExpiry);
            _term.setUnderlyingReturnValue(_testCases[i].underlying);
            _term.setUserBalance(assetId, user, _testCases[i].userBalance);
            _term.setTotalSupply(assetId, _testCases[i].totalSupply);

            // Expect an error to occur with the required bytes.
            vm.expectRevert(_testCases[i].expectedError);

            // Attempt to release the PT.
            _term.releasePTExternal(
                finalState,
                assetId,
                user,
                _testCases[i].amount
            );
        }
    }

    // This test runs through the full testing matrix of cases in which an
    // underlying value of zero causes a division by zero error.
    function testReleasePTExpectsRevert__zeroUnderlying() public {
        // All of these test cases should fail with a division by zero error
        // on account of the underlying being zero.
        FailureTestCaseReleasePT[32] memory testCases = [
            // Choose 0 out of 5 - 1 case.
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 0,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 0,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            // Choose 1 out of 5 - 5 cases.
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 0,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 0,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 1 ether,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 0,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 0,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 0,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 0,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 0,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 0,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            // Choose 2 out of 5 - 10 cases
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 1 ether,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 0,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 0,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 0,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 0,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 0,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 0,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 1 ether,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 0,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 1 ether,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 1 ether,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 0,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 0,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 0,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 0,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 0,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            // Choose 3 out of 5 - 10 cases
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 1 ether,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 0,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 1 ether,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 1 ether,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 0,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 0,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 0,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 0,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 0,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 1 ether,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 1 ether,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 0,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 1 ether,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 0,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            // Choose 4 out of 5 - 5 cases
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 1 ether,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 0,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 1 ether,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 0,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 1 ether,
                sharesPerExpiry: 0,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 0,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            FailureTestCaseReleasePT({
                amount: 0,
                interest: 1 ether,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            }),
            // Choose 5 out of 5 - 1 case
            FailureTestCaseReleasePT({
                amount: 1 ether,
                interest: 1 ether,
                sharesPerExpiry: 1 ether,
                underlying: 0,
                userBalance: 1 ether,
                totalSupply: 1 ether,
                expectedError: stdError.divisionError
            })
        ];

        FailureTestCaseReleasePT[]
            memory testCasesReified = new FailureTestCaseReleasePT[](32);
        for (uint256 i = 0; i < testCases.length; i++) {
            testCasesReified[i] = testCases[i];
        }
        executeReleasePTFailureTestCases(testCasesReified);
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
