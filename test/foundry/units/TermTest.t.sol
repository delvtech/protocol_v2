// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/libraries/Errors.sol";
import "contracts/mocks/MockTerm.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "../Utils.sol";

contract TermTest is Test {
    address public destination = vm.addr(0xBEEF_DEAD);
    address public source = vm.addr(0xDEAD_BEEF);

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

    // ----------------------- mock events -----------------------//

    event FinalizeTerm(uint256 expiry);
    event ReleasePT(
        Term.FinalizedState finalState,
        uint256 assetId,
        address source,
        uint256 amount
    );
    event ReleaseYT(
        Term.FinalizedState finalState,
        uint256 assetId,
        address source,
        uint256 amount
    );
    event ReleaseUnlocked(address source, uint256 amount);

    // -------------------  _createYT unit tests   ------------------ //

    // FIXME:
    //
    // There are no checks to verify that the term is expired.

    // FIXME:
    //
    // Ensure that users that _createYT in the same block as the
    // the person that created the YT term are treated fairly.

    // FIXME
    //
    // Whiteboard out the calculations for unlocked vs locked accounting.

    // FIXME:
    //
    // I can't tell where there is a penalty applied for creating yield
    // tokens with later start dates. Revisit the lock accounting to see
    // how the totalShares figure is calculated.

    // FIXME:
    //
    // Really pay attention to the discounting math. Think about how this
    // works at various points in time (soon after the term is created,
    // awhile after the term is created, right before finalization), with
    // several values being minted.

    function testCombinatorialCreateYT() public {
        // Set up the fixed values.
        startHoax(source);
        vm.warp(5_000);

        uint256[][] memory inputs = new uint256[][](7);
        // shared inputs
        uint256[] memory amountInputs = new uint256[](3);
        amountInputs[0] = 0;
        // TODO: This fails if using low value inputs (ex. 123).
        amountInputs[1] = 1 ether;
        amountInputs[2] = 1.324 ether + 734;
        uint256[] memory timeInputs = new uint256[](3);
        // TODO: There isn't currently a check on whether or not the start
        // date is zero.
        timeInputs[0] = 0;
        // TODO: There isn't currently a check on whether or not the expiry
        // has already been reached.
        timeInputs[1] = block.timestamp - 1_000;
        timeInputs[2] = 2 * block.timestamp;
        // value inputs
        inputs[0] = amountInputs;
        // total shares inputs
        inputs[1] = amountInputs;
        // start time inputs
        inputs[2] = timeInputs;
        // expiration inputs
        inputs[3] = timeInputs;
        // yieldState.shares inputs
        inputs[4] = amountInputs;
        // yieldState.pt inputs
        inputs[5] = amountInputs;
        // total supply inputs
        inputs[6] = amountInputs;
        // generate the testing matrix
        CreateYTTestCase[] memory testCases = convertToCreateYTTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        for (uint256 i = 0; i < testCases.length; i++) {
            // Set up the test state.
            uint256 assetId = Utils.encodeAssetId(
                true,
                testCases[i].startTime,
                testCases[i].expiration
            );
            _term.setSharesPerExpiry(
                testCases[i].expiration,
                testCases[i].yieldState.shares
            );
            _term.setUserBalance(assetId, destination, 0);
            _term.setTotalSupply(assetId, testCases[i].totalSupply);
            _term.setYieldState(assetId, testCases[i].yieldState);

            bytes memory expectedError = getExpectedErrorCreateYT(testCases[i]);
            if (expectedError.length > 0) {
                try
                    _term.createYTExternal(
                        destination,
                        testCases[i].value,
                        testCases[i].totalShares,
                        testCases[i].startTime,
                        testCases[i].expiration
                    )
                {
                    logTestCaseCreateYT("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (
                        keccak256(abi.encodePacked(error)) !=
                        keccak256(abi.encodePacked(expectedError))
                    ) {
                        logTestCaseCreateYT("failure case", testCases[i]);
                        assertEq(error, expectedError);
                    }
                }
            } else {
                try
                    _term.createYTExternal(
                        destination,
                        testCases[i].value,
                        testCases[i].totalShares,
                        testCases[i].startTime,
                        testCases[i].expiration
                    )
                returns (uint256 amount) {
                    validateCreateYTSuccess(testCases[i], amount);
                } catch (bytes memory error) {
                    logTestCaseCreateYT("success case", testCases[i]);
                    revert("failed unexpectedly");
                }
            }
        }
    }

    struct CreateYTTestCase {
        uint256 value;
        uint256 totalShares;
        uint256 startTime;
        uint256 expiration;
        Term.YieldState yieldState;
        uint256 totalSupply;
    }

    function convertToCreateYTTestCase(uint256[][] memory rawTestMatrix)
        internal
        pure
        returns (CreateYTTestCase[] memory)
    {
        CreateYTTestCase[] memory result = new CreateYTTestCase[](
            rawTestMatrix.length
        );
        for (uint256 i = 0; i < rawTestMatrix.length; i++) {
            require(
                rawTestMatrix[i].length == 7,
                "Raw test case must have length of 7."
            );
            result[i] = CreateYTTestCase({
                value: rawTestMatrix[i][0],
                totalShares: rawTestMatrix[i][1],
                startTime: rawTestMatrix[i][2],
                expiration: rawTestMatrix[i][3],
                yieldState: Term.YieldState({
                    shares: uint128(rawTestMatrix[i][4]),
                    pt: uint128(rawTestMatrix[i][5])
                }),
                totalSupply: rawTestMatrix[i][6]
            });
        }
        return result;
    }

    function getExpectedErrorCreateYT(CreateYTTestCase memory testCase)
        internal
        view
        returns (bytes memory)
    {
        if (testCase.expiration != 0 && testCase.startTime != block.timestamp) {
            if (
                testCase.yieldState.shares == 0 || testCase.yieldState.pt == 0
            ) {
                return
                    abi.encodeWithSelector(
                        ElementError.TermNotInitialized.selector
                    );
            }
            if (testCase.totalShares == 0) {
                return stdError.divisionError;
            }
            uint256 expectedImpliedShareValue = (testCase.value *
                uint256(testCase.yieldState.shares)) / testCase.totalShares;
            if (expectedImpliedShareValue < uint256(testCase.yieldState.pt)) {
                return stdError.arithmeticError;
            }
            if (testCase.totalSupply == 0) {
                return stdError.divisionError;
            }
            uint256 expectedInterestEarned = expectedImpliedShareValue -
                uint256(testCase.yieldState.pt);
            uint256 expectedTotalDiscount = (testCase.value *
                expectedInterestEarned) / testCase.totalSupply;
            // TODO: This seems like it will never happen, so we should
            // definitely revisit this.
            if (expectedTotalDiscount > testCase.totalShares) {
                return stdError.arithmeticError;
            }
            // TODO: This seems like it will never happen, so we should
            // definitely revisit this.
            if (expectedTotalDiscount > testCase.value) {
                return stdError.arithmeticError;
            }
        }
        return new bytes(0);
    }

    function validateCreateYTSuccess(
        CreateYTTestCase memory testCase,
        uint256 amount
    ) internal {
        if (testCase.expiration == 0) {
            uint256 assetId = _term.UNLOCKED_YT_ID();
            if (amount != testCase.value) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(amount, testCase.value, "unexpected value");
            }
            uint256 balance = _term.balanceOf(assetId, destination);
            if (balance != testCase.totalShares) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    balance,
                    testCase.totalShares,
                    "unexpected destination balance"
                );
            }
            uint256 totalSupply = _term.totalSupply(assetId);
            if (totalSupply != testCase.totalSupply + testCase.totalShares) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    totalSupply,
                    testCase.totalSupply + testCase.totalShares,
                    "unexpected total supply"
                );
            }
            (uint256 shares, uint256 pt) = _term.yieldTerms(assetId);
            if (shares != testCase.yieldState.shares + testCase.totalShares) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    shares,
                    testCase.yieldState.shares + testCase.totalShares,
                    "unexpected yieldState.shares"
                );
            }
            if (pt != testCase.yieldState.pt) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    pt,
                    testCase.yieldState.pt,
                    "unexpected yieldState.pt"
                );
            }
        } else if (
            testCase.startTime == block.timestamp && testCase.yieldState.pt == 0
        ) {
            uint256 assetId = Utils.encodeAssetId(
                true,
                testCase.startTime,
                testCase.expiration
            );
            if (amount != 0) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(amount, 0, "unexpected value");
            }
            uint256 balance = _term.balanceOf(assetId, destination);
            if (balance != testCase.value) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    balance,
                    testCase.value,
                    "unexpected destination balance"
                );
            }
            uint256 totalSupply = _term.totalSupply(assetId);
            if (totalSupply != testCase.totalSupply + testCase.value) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    totalSupply,
                    testCase.totalSupply + testCase.value,
                    "unexpected total supply"
                );
            }
            uint256 sharesPerExpiry = _term.sharesPerExpiry(
                testCase.expiration
            );
            if (
                sharesPerExpiry !=
                testCase.yieldState.shares + testCase.totalShares
            ) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    sharesPerExpiry,
                    testCase.yieldState.shares + testCase.totalShares,
                    "unexpected sharesPerExpiry"
                );
            }
            (uint256 shares, uint256 pt) = _term.yieldTerms(assetId);
            if (shares != testCase.yieldState.shares + testCase.totalShares) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    shares,
                    testCase.yieldState.shares + testCase.totalShares,
                    "unexpected yieldState.shares"
                );
            }
            if (pt != testCase.yieldState.pt + testCase.value) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    pt,
                    testCase.yieldState.pt + testCase.value,
                    "unexpected yieldState.pt"
                );
            }
        } else {
            uint256 assetId = Utils.encodeAssetId(
                true,
                testCase.startTime,
                testCase.expiration
            );
            // TODO: Revisit these calculations in more depth. Better
            //       documentation that explains how all of the accounting
            //       fits together would do wonders.
            uint256 expectedImpliedShareValue = (testCase.yieldState.shares *
                testCase.value) / testCase.totalShares;
            uint256 expectedInterestEarned = expectedImpliedShareValue -
                testCase.yieldState.pt;
            uint256 expectedTotalDiscount = (testCase.value *
                expectedInterestEarned) / testCase.totalSupply;
            if (amount != expectedTotalDiscount) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(amount, expectedTotalDiscount, "unexpected amount");
            }
            uint256 balance = _term.balanceOf(assetId, destination);
            if (balance != testCase.value) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(balance, testCase.value, "unexpected balance");
            }
            uint256 totalSupply = _term.totalSupply(assetId);
            if (totalSupply != testCase.totalSupply + testCase.value) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    totalSupply,
                    testCase.totalSupply + testCase.value,
                    "unexpected total supply"
                );
            }
            uint256 sharesPerExpiry = _term.sharesPerExpiry(
                testCase.expiration
            );
            if (
                sharesPerExpiry !=
                testCase.yieldState.shares + testCase.totalShares
            ) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    sharesPerExpiry,
                    testCase.yieldState.shares + testCase.totalShares,
                    "unexpected sharesPerExpiry"
                );
            }
            (uint256 shares, uint256 pt) = _term.yieldTerms(assetId);
            if (shares != testCase.yieldState.shares + testCase.totalShares) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    shares,
                    testCase.yieldState.shares + testCase.totalShares,
                    "unexpected yieldState.shares"
                );
            }
            if (pt != testCase.yieldState.pt + testCase.value) {
                logTestCaseCreateYT("success case", testCase);
                assertEq(
                    pt,
                    testCase.yieldState.pt +
                        testCase.value -
                        expectedTotalDiscount,
                    "unexpected yieldState.pt"
                );
            }
        }
    }

    function logTestCaseCreateYT(
        string memory prelude,
        CreateYTTestCase memory testCase
    ) internal view {
        console.log(prelude);
        console.log("");
        console.log("    value             = ", testCase.value);
        console.log("    totalShares       = ", testCase.totalShares);
        console.log("    startTime         = ", testCase.startTime);
        console.log("    expiration        = ", testCase.expiration);
        console.log("    yieldState.shares = ", testCase.yieldState.shares);
        console.log("    yieldState.pt     = ", testCase.yieldState.pt);
        console.log("    totalSupply       = ", testCase.totalSupply);
        console.log("");
    }

    // -------------------  _releaseAsset unit tests   ------------------ //

    function testCombinatorialReleaseAsset() public {
        uint256[][] memory inputs = new uint256[][](3);
        // amount and interest inputs
        uint256[] memory innerInputs = new uint256[](4);
        innerInputs[0] = 0;
        innerInputs[1] = 923094;
        innerInputs[2] = 1.82354 ether;
        innerInputs[3] = 2.432 ether + 98234;
        inputs[0] = innerInputs;
        inputs[2] = innerInputs;
        // asset id inputs
        inputs[1] = new uint256[](7);
        inputs[1][0] = Utils.encodeAssetId(false, 0, 0);
        inputs[1][1] = Utils.encodeAssetId(false, 0, 23423);
        inputs[1][2] = Utils.encodeAssetId(true, 0, 0);
        inputs[1][3] = Utils.encodeAssetId(true, 0, 893);
        inputs[1][4] = Utils.encodeAssetId(true, 3242, 893);
        inputs[1][5] = Utils.encodeAssetId(true, 0, 98234);
        inputs[1][6] = Utils.encodeAssetId(true, 432534, 98234);
        ReleaseAssetTestCase[] memory testCases = convertToReleaseAssetTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        // Set the address.
        startHoax(source);

        // Set the block timestamp so that we can test the expiry.
        vm.warp(5_000);

        for (uint256 i = 0; i < testCases.length; i++) {
            // Set up the test state.
            (, , uint256 expiry) = _term.parseAssetIdExternal(
                testCases[i].assetId
            );
            _term.setFinalizedState(
                expiry,
                Term.FinalizedState({
                    pricePerShare: 1 ether,
                    interest: testCases[i].interest
                })
            );

            bytes memory expectedError = getExpectedErrorReleaseAsset(
                testCases[i]
            );
            if (expectedError.length > 0) {
                try
                    _term.releaseAssetExternal(
                        testCases[i].assetId,
                        source,
                        testCases[i].amount
                    )
                {
                    logTestCaseReleaseAsset("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (
                        keccak256(abi.encodePacked(error)) !=
                        keccak256(abi.encodePacked(expectedError))
                    ) {
                        logTestCaseReleaseAsset("failure case", testCases[i]);
                        assertEq(error, expectedError);
                    }
                }
            } else {
                registerExpectedEventsReleaseAsset(testCases[i]);
                try
                    _term.releaseAssetExternal(
                        testCases[i].assetId,
                        source,
                        testCases[i].amount
                    )
                returns (uint256 shares, uint256 value) {
                    // The mocks always return (1, 2). We have other unit
                    // tests that verify that the `_release*` functions for
                    // different assets return the correct values.
                    assertEq(shares, 1);
                    assertEq(value, 2);
                } catch (bytes memory error) {
                    logTestCaseReleaseAsset("success case", testCases[i]);
                    revert("failed unexpectedly");
                }
            }
        }
    }

    struct ReleaseAssetTestCase {
        uint256 amount;
        uint256 assetId;
        // TODO: We considered changing this check to use pricePerShare
        // instead of interest.
        uint128 interest;
    }

    function convertToReleaseAssetTestCase(uint256[][] memory rawTestMatrix)
        internal
        pure
        returns (ReleaseAssetTestCase[] memory)
    {
        ReleaseAssetTestCase[] memory result = new ReleaseAssetTestCase[](
            rawTestMatrix.length
        );
        for (uint256 i = 0; i < rawTestMatrix.length; i++) {
            require(
                rawTestMatrix[i].length == 3,
                "Raw test case must have length of 3."
            );
            result[i] = ReleaseAssetTestCase({
                amount: rawTestMatrix[i][0],
                assetId: rawTestMatrix[i][1],
                interest: uint128(rawTestMatrix[i][2])
            });
        }
        return result;
    }

    function getExpectedErrorReleaseAsset(ReleaseAssetTestCase memory testCase)
        internal
        view
        returns (bytes memory)
    {
        (, , uint256 expiry) = _term.parseAssetIdExternal(testCase.assetId);
        if (expiry < 5_000 && expiry != 0) {
            return abi.encodeWithSelector(ElementError.TermNotExpired.selector);
        }
        return new bytes(0);
    }

    function registerExpectedEventsReleaseAsset(
        ReleaseAssetTestCase memory testCase
    ) internal {
        (bool isYieldToken, , uint256 expiry) = _term.parseAssetIdExternal(
            testCase.assetId
        );
        if (testCase.assetId == _term.UNLOCKED_YT_ID()) {
            vm.expectEmit(true, true, true, true);
            emit ReleaseUnlocked(source, testCase.amount);
            return;
        }
        Term.FinalizedState memory finalState = Term.FinalizedState({
            pricePerShare: 1 ether,
            interest: testCase.interest
        });
        if (testCase.interest == 0) {
            vm.expectEmit(true, true, true, true);
            emit FinalizeTerm(expiry);
            // If _finalizeTerm is called, we expect the final state to
            // consist of a price per share of 1 wei and a interest of 2
            // wei.
            finalState = Term.FinalizedState({ pricePerShare: 1, interest: 2 });
        }
        if (isYieldToken) {
            vm.expectEmit(true, true, true, true);
            emit ReleaseYT(
                finalState,
                testCase.assetId,
                source,
                testCase.amount
            );
        } else {
            vm.expectEmit(true, true, true, true);
            emit ReleasePT(
                finalState,
                testCase.assetId,
                source,
                testCase.amount
            );
        }
    }

    function logTestCaseReleaseAsset(
        string memory prelude,
        ReleaseAssetTestCase memory testCase
    ) internal view {
        console.log(prelude);
        console.log("");
        console.log("    amount   = ", testCase.amount);
        console.log("    assetId  = ", testCase.assetId);
        console.log("    interest = ", testCase.interest);
        console.log("");
    }

    // -------------------  _finalizeTerm unit tests   ------------------ //

    function testCombinatorialFinalizeTerm() public {
        // TODO: There were some failures when using inputs below 1e18.
        // Think more about this and make sure to test with these inputs
        // elsewhere in the codebase.
        uint256[] memory innerInputs = new uint256[](5);
        innerInputs[0] = 0;
        innerInputs[1] = 1 ether;
        innerInputs[2] = 1.5435 ether + 23423;
        innerInputs[3] = 2 ether;
        innerInputs[4] = 10 ether + 89534;
        uint256[][] memory inputs = new uint256[][](3);
        for (uint256 i = 0; i < inputs.length; i++) {
            inputs[i] = innerInputs;
        }
        FinalizeTermTestCase[] memory testCases = convertToFinalizeTermTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        // Set the address.
        startHoax(source);

        // We pick a fixed expiry since it wouldn't effect the testing to
        // simulate different values for the parameter.
        uint256 expiry = 10_000;

        for (uint256 i = 0; i < testCases.length; i++) {
            // Set up the test state.
            _term.setCurrentPricePerShare(testCases[i].currentPricePerShare);
            _term.setSharesPerExpiry(expiry, testCases[i].sharesPerExpiry);
            _term.setTotalSupply(expiry, testCases[i].totalSupply);

            bytes memory expectedError = getExpectedErrorFinalizeTerm(
                testCases[i]
            );
            if (expectedError.length > 0) {
                try _term.finalizeTermExternal(expiry) {
                    logTestCaseFinalizeTerm("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (
                        keccak256(abi.encodePacked(error)) !=
                        keccak256(abi.encodePacked(expectedError))
                    ) {
                        logTestCaseFinalizeTerm("failure case", testCases[i]);
                        assertEq(error, expectedError);
                    }
                }
            } else {
                try _term.finalizeTermExternal(expiry) returns (
                    Term.FinalizedState memory finalState
                ) {
                    validateFinalizeTermSuccess(
                        testCases[i],
                        finalState,
                        expiry
                    );
                } catch (bytes memory error) {
                    logTestCaseFinalizeTerm("success case", testCases[i]);
                    revert("failed unexpectedly");
                }
            }
        }
    }

    struct FinalizeTermTestCase {
        uint256 currentPricePerShare;
        uint256 sharesPerExpiry;
        uint256 totalSupply;
    }

    function convertToFinalizeTermTestCase(uint256[][] memory rawTestMatrix)
        internal
        pure
        returns (FinalizeTermTestCase[] memory)
    {
        FinalizeTermTestCase[] memory result = new FinalizeTermTestCase[](
            rawTestMatrix.length
        );
        for (uint256 i = 0; i < rawTestMatrix.length; i++) {
            require(
                rawTestMatrix[i].length == 3,
                "Raw test case must have length of 3."
            );
            result[i] = FinalizeTermTestCase({
                currentPricePerShare: rawTestMatrix[i][0],
                sharesPerExpiry: rawTestMatrix[i][1],
                totalSupply: rawTestMatrix[i][2]
            });
        }
        return result;
    }

    function getExpectedErrorFinalizeTerm(FinalizeTermTestCase memory testCase)
        internal
        pure
        returns (bytes memory)
    {
        if (testCase.sharesPerExpiry == 0) {
            return stdError.divisionError;
        }
        return new bytes(0);
    }

    function validateFinalizeTermSuccess(
        FinalizeTermTestCase memory testCase,
        Term.FinalizedState memory finalState,
        uint256 expiry
    ) internal {
        // Ensure that the return value is correct.
        uint256 expectedPricePerShare = testCase.currentPricePerShare;
        if (
            stdMath.delta(finalState.pricePerShare, expectedPricePerShare) > 1
        ) {
            logTestCaseFinalizeTerm("success case", testCase);
            assertApproxEqAbs(
                finalState.pricePerShare,
                expectedPricePerShare,
                1,
                "unexpected pricePerShare in return"
            );
        }
        // TODO: Double check on the how the release and withdrawal flows work
        // with different cases of finalized interest and accrued interest
        // after the fact.
        uint256 expectedTotalValue = (testCase.currentPricePerShare *
            testCase.sharesPerExpiry) / _term.one();
        uint256 expectedInterest = testCase.totalSupply > expectedTotalValue
            ? 0
            : expectedTotalValue - testCase.totalSupply;
        if (finalState.interest != expectedInterest) {
            logTestCaseFinalizeTerm("success case", testCase);
            assertEq(
                finalState.interest,
                expectedInterest,
                "unexpected interest in return"
            );
        }

        // Ensure that the finalized state was updated correctly.
        (uint256 pricePerShare, uint256 interest) = _term.finalizedTerms(
            expiry
        );
        if (stdMath.delta(pricePerShare, expectedPricePerShare) > 1) {
            logTestCaseFinalizeTerm("success case", testCase);
            assertApproxEqAbs(
                pricePerShare,
                expectedPricePerShare,
                1,
                "unexpected pricePerShare in state"
            );
        }
        if (interest != expectedInterest) {
            logTestCaseFinalizeTerm("success case", testCase);
            assertEq(
                interest,
                expectedInterest,
                "unexpected interest in state"
            );
        }
    }

    function logTestCaseFinalizeTerm(
        string memory prelude,
        FinalizeTermTestCase memory testCase
    ) internal view {
        console.log(prelude);
        console.log("");
        console.log(
            "    currentPricePerShare =",
            testCase.currentPricePerShare
        );
        console.log("    sharesPerExpiry      =", testCase.sharesPerExpiry);
        console.log("    totalSupply          =", testCase.totalSupply);
        console.log("");
    }

    // -------------------  _releaseUnlocked unit tests   ------------------ //

    function testCombinatorialReleaseUnlocked() public {
        uint256[] memory innerInputs = new uint256[](5);
        innerInputs[0] = 0;
        innerInputs[1] = 1 ether;
        innerInputs[2] = 2 ether;
        innerInputs[3] = 123;
        innerInputs[4] = 10 ether + 89534;
        uint256[][] memory inputs = new uint256[][](5);
        for (uint256 i = 0; i < inputs.length; i++) {
            inputs[i] = innerInputs;
        }
        ReleaseUnlockedTestCase[]
            memory testCases = convertToReleaseUnlockedTestCase(
                Utils.generateTestingMatrix(inputs)
            );

        // Set the address.
        startHoax(source);

        uint256 unlockedYTId = _term.UNLOCKED_YT_ID();
        for (uint256 i = 0; i < testCases.length; i++) {
            // Set up the test state.
            _term.setCurrentPricePerShare(testCases[i].currentPricePerShare);
            _term.setTotalSupply(unlockedYTId, testCases[i].totalSupply);
            _term.setUserBalance(
                unlockedYTId,
                source,
                testCases[i].sourceBalance
            );
            _term.setYieldState(
                unlockedYTId,
                Term.YieldState({
                    shares: uint128(testCases[i].shares),
                    pt: 1 ether
                })
            );

            bytes memory expectedError = getExpectedErrorReleaseUnlocked(
                testCases[i]
            );
            if (expectedError.length > 0) {
                try _term.releaseUnlockedExternal(source, testCases[i].amount) {
                    logTestCaseReleaseUnlocked("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (
                        keccak256(abi.encodePacked(error)) !=
                        keccak256(abi.encodePacked(expectedError))
                    ) {
                        logTestCaseReleaseUnlocked(
                            "failure case",
                            testCases[i]
                        );
                        assertEq(error, expectedError);
                    }
                }
            } else {
                try
                    _term.releaseUnlockedExternal(source, testCases[i].amount)
                returns (uint256 shares, uint256 value) {
                    validateReleaseUnlockedSuccess(testCases[i], shares, value);
                } catch (bytes memory error) {
                    logTestCaseReleaseUnlocked("success case", testCases[i]);
                    revert("failed unexpectedly");
                }
            }
        }
    }

    struct ReleaseUnlockedTestCase {
        uint256 amount;
        // The current price for a single unlocked YT. We multiply this
        // by the expected source shares to get the return value of
        // _underlying.
        uint256 currentPricePerShare;
        uint256 shares;
        uint256 totalSupply;
        uint256 sourceBalance;
    }

    function convertToReleaseUnlockedTestCase(uint256[][] memory rawTestMatrix)
        internal
        pure
        returns (ReleaseUnlockedTestCase[] memory)
    {
        ReleaseUnlockedTestCase[] memory result = new ReleaseUnlockedTestCase[](
            rawTestMatrix.length
        );
        for (uint256 i = 0; i < rawTestMatrix.length; i++) {
            require(
                rawTestMatrix[i].length == 5,
                "Raw test case must have length of 5."
            );
            result[i] = ReleaseUnlockedTestCase({
                amount: rawTestMatrix[i][0],
                currentPricePerShare: rawTestMatrix[i][1],
                shares: rawTestMatrix[i][2],
                totalSupply: rawTestMatrix[i][3],
                sourceBalance: rawTestMatrix[i][4]
            });
        }
        return result;
    }

    function getExpectedErrorReleaseUnlocked(
        ReleaseUnlockedTestCase memory testCase
    ) internal pure returns (bytes memory) {
        if (testCase.totalSupply == 0) {
            return stdError.divisionError;
        } else if (
            testCase.amount > testCase.totalSupply ||
            testCase.amount > testCase.sourceBalance
        ) {
            return stdError.arithmeticError;
        }
        return new bytes(0);
    }

    function validateReleaseUnlockedSuccess(
        ReleaseUnlockedTestCase memory testCase,
        uint256 shares,
        uint256 value
    ) internal {
        // Ensure that the return values are correct.
        uint256 expectedShares = (testCase.shares * testCase.amount) /
            testCase.totalSupply;
        uint256 expectedValue = (expectedShares *
            testCase.currentPricePerShare) / _term.one();
        if (shares != expectedShares) {
            logTestCaseReleaseUnlocked("success case", testCase);
            assertEq(shares, expectedShares, "unexpected shares");
        }
        if (value != expectedValue) {
            logTestCaseReleaseUnlocked("success case", testCase);
            assertEq(value, expectedValue, "unexpected value");
        }

        // Ensure that the state was updated correctly.
        uint256 unlockedYTId = _term.UNLOCKED_YT_ID();
        uint256 totalSupply = _term.totalSupply(unlockedYTId);
        uint256 sourceBalance = _term.balanceOf(unlockedYTId, source);
        if (totalSupply != testCase.totalSupply - testCase.amount) {
            logTestCaseReleaseUnlocked("success case", testCase);
            assertEq(
                totalSupply,
                testCase.totalSupply - testCase.amount,
                "unexpected totalSupply"
            );
        }
        if (sourceBalance != testCase.sourceBalance - testCase.amount) {
            logTestCaseReleaseUnlocked("success case", testCase);
            assertEq(
                sourceBalance,
                testCase.sourceBalance - testCase.amount,
                "unexpected sourceBalance"
            );
        }
        (uint128 shares, ) = _term.yieldTerms(unlockedYTId);
        if (shares != testCase.shares - expectedShares) {
            logTestCaseReleaseUnlocked("success case", testCase);
            assertEq(
                shares,
                testCase.shares - expectedShares,
                "unexpected shares"
            );
        }
    }

    function logTestCaseReleaseUnlocked(
        string memory prelude,
        ReleaseUnlockedTestCase memory testCase
    ) internal view {
        console.log(prelude);
        console.log("");
        console.log("    amount = ", testCase.amount);
        console.log(
            "    currentPricePerShare = ",
            testCase.currentPricePerShare
        );
        console.log("    shares               = ", testCase.shares);
        console.log("    totalSupply          = ", testCase.totalSupply);
        console.log("    sourceBalance          = ", testCase.sourceBalance);
        console.log("");
    }

    // -------------------  _releaseYT unit tests   ------------------ //

    function testCombinatorialReleaseYT() public {
        // Get the test cases. We're using inputs with lots of digits
        // since there aren't any failure cases relying on inputs being
        // multiples. We can only use three inputs since 4 ** 9 cases blows
        // over foundry's gas limit (TODO: Consider making a PR to Foundry to
        // make foundry's gas limit larger since executing this amount of test
        // cases is pretty reasonable from a time perspective).
        uint256[] memory innerInputs = new uint256[](3);
        innerInputs[0] = 0;
        innerInputs[1] = 1.8349 ether + 808324;
        innerInputs[2] = 2.2342 ether + 838903;
        uint256[][] memory inputs = new uint256[][](9);
        for (uint256 i = 0; i < inputs.length; i++) {
            inputs[i] = innerInputs;
        }
        ReleaseYTTestCase[] memory testCases = convertToReleaseYTTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        // Set the address.
        startHoax(source);

        // Create an asset ID of a PT that expires at 10,000.
        uint256 start = 5_000;
        uint256 expiry = 10_000;
        uint256 assetId = Utils.encodeAssetId(true, start, expiry);

        for (uint256 i = 0; i < testCases.length; i++) {
            // Set up the test's state in the term contract.
            Term.FinalizedState memory finalState = testCases[i].finalState;
            _term.setFinalizedState(expiry, testCases[i].finalState);
            _term.setSharesPerExpiry(expiry, testCases[i].sharesPerExpiry);
            _term.setTotalSupply(assetId, testCases[i].totalSupply);
            _term.setCurrentPricePerShare(testCases[i].currentPricePerShare);
            _term.setUserBalance(assetId, source, testCases[i].sourceBalance);
            _term.setYieldState(assetId, testCases[i].yieldState);

            bytes memory expectedError = getExpectedErrorReleaseYT(
                testCases[i]
            );
            if (expectedError.length > 0) {
                try
                    _term.releaseYTExternal(
                        finalState,
                        assetId,
                        source,
                        testCases[i].amount
                    )
                {
                    logTestCaseReleaseYT("failure case", testCases[i]);
                    revert("succeeded unexpectedly.");
                } catch (bytes memory error) {
                    if (
                        keccak256(abi.encodePacked(error)) !=
                        keccak256(abi.encodePacked(expectedError))
                    ) {
                        logTestCaseReleaseYT("failure case", testCases[i]);
                        assertEq(error, expectedError);
                    }
                }
            } else {
                try
                    _term.releaseYTExternal(
                        finalState,
                        assetId,
                        source,
                        testCases[i].amount
                    )
                returns (uint256 shares, uint256 value) {
                    validateReleaseYTSuccess(
                        testCases[i],
                        assetId,
                        shares,
                        value
                    );
                } catch (bytes memory error) {
                    logTestCaseReleaseYT("success case", testCases[i]);
                    revert("failed unexpectedly");
                }
            }
        }
    }

    struct ReleaseYTTestCase {
        // The amount of YT to release.
        uint256 amount;
        // The current price of one share. This is the return value of the
        // _underlying function.
        uint256 currentPricePerShare;
        // TODO: This is used in two ways. First, it's used as a parameter, but
        // it's also accessed directly as a state variable. Consider if this is
        // is appropriate. If so, document why. If not, change it.
        //
        // The finalized price per share and interest. This is used to
        // calculate the amount of value that a given number of YT shares will
        // be worth.
        Term.FinalizedState finalState;
        // The amount of shares outstanding in the term.
        uint256 sharesPerExpiry;
        // The total supply of the YT token for this term.
        uint256 totalSupply;
        // The balance of YT that the source will be given.
        uint256 sourceBalance;
        // The yield state that should be set for the asset ID.
        Term.YieldState yieldState;
    }

    // Converts a raw testing matrix to a structured array.
    function convertToReleaseYTTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (ReleaseYTTestCase[] memory testCases)
    {
        testCases = new ReleaseYTTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 9,
                "Raw test case must have length of 9."
            );
            testCases[i] = ReleaseYTTestCase({
                amount: rawTestCases[i][0],
                currentPricePerShare: rawTestCases[i][1],
                finalState: Term.FinalizedState({
                    pricePerShare: uint128(rawTestCases[i][2]),
                    interest: uint128(rawTestCases[i][3])
                }),
                sharesPerExpiry: rawTestCases[i][4],
                totalSupply: rawTestCases[i][5],
                sourceBalance: rawTestCases[i][6],
                yieldState: Term.YieldState({
                    shares: uint128(rawTestCases[i][7]),
                    pt: uint128(rawTestCases[i][8])
                })
            });
        }
    }

    function getExpectedReturnValuesReleaseYT(ReleaseYTTestCase memory testCase)
        internal
        view
        returns (uint256, uint256)
    {
        // TODO: It's unfortunate to need to replicate all of this logic here.
        // Think about how this could be simplified or avoided (one thought is
        // that this could be a separate function that gets tested separately,
        // but we may just be pushing the problem off further.
        uint256 termEndingValue = (uint256(testCase.yieldState.shares) *
            uint256(testCase.finalState.pricePerShare)) / _term.one();
        uint256 termEndingInterest = testCase.yieldState.pt > termEndingValue
            ? 0
            : termEndingValue - testCase.yieldState.pt;
        uint256 sourceInterest = (termEndingInterest * testCase.amount) /
            testCase.totalSupply;
        uint256 sourceShares = (sourceInterest * _term.one()) /
            testCase.currentPricePerShare;
        return (sourceShares, sourceInterest);
    }

    // Given a test case, get the expected error that will be thrown by a failed
    // call to _releaseYT.
    function getExpectedErrorReleaseYT(ReleaseYTTestCase memory testCase)
        internal
        view
        returns (bytes memory)
    {
        if (testCase.totalSupply == 0) {
            return stdError.divisionError;
        } else if (testCase.currentPricePerShare == 0) {
            return stdError.divisionError;
        }
        (
            uint256 sourceShares,
            uint256 sourceInterest
        ) = getExpectedReturnValuesReleaseYT(testCase);
        if (sourceShares > testCase.sharesPerExpiry) {
            return stdError.arithmeticError;
        } else if (sourceInterest > testCase.finalState.interest) {
            return stdError.arithmeticError;
        } else if (
            testCase.amount > testCase.sourceBalance ||
            testCase.amount > testCase.totalSupply
        ) {
            return stdError.arithmeticError;
        }
        return new bytes(0);
    }

    // Given a test case, validate the state transitions and return values of a
    // successful call to _releaseYT.
    function validateReleaseYTSuccess(
        ReleaseYTTestCase memory testCase,
        uint256 assetId,
        uint256 shares,
        uint256 value
    ) internal {
        // Ensure that the calculated shares and value are correct.
        (
            uint256 expectedShares,
            uint256 expectedValue
        ) = getExpectedReturnValuesReleaseYT(testCase);
        if (shares != expectedShares) {
            logTestCaseReleaseYT("success case", testCase);
            assertEq(shares, expectedShares, "unexpected shares");
        }
        if (value != expectedValue) {
            logTestCaseReleaseYT("success case", testCase);
            assertEq(value, expectedValue, "unexpected value");
        }

        // Ensure that the state was updated correctly.
        (, , uint256 expiry) = _term.parseAssetIdExternal(assetId);
        (uint128 pricePerShare, uint128 interest) = _term.finalizedTerms(
            expiry
        );
        // TODO: These could be helper functions in Test.sol
        if (pricePerShare != testCase.finalState.pricePerShare) {
            logTestCaseReleaseYT("success case", testCase);
            assertEq(
                pricePerShare,
                testCase.finalState.pricePerShare,
                "unexpected pricePerShare"
            );
        }
        if (interest != testCase.finalState.interest - expectedValue) {
            logTestCaseReleaseYT("success case", testCase);
            assertEq(
                interest,
                testCase.finalState.interest - expectedValue,
                "unexpected interest"
            );
        }
        if (
            _term.sharesPerExpiry(expiry) !=
            testCase.sharesPerExpiry - expectedShares
        ) {
            logTestCaseReleaseYT("success case", testCase);
            assertEq(
                _term.sharesPerExpiry(expiry),
                testCase.sharesPerExpiry - expectedShares,
                "unexpected sharesPerExpiry"
            );
        }
        if (
            _term.totalSupply(assetId) != testCase.totalSupply - testCase.amount
        ) {
            logTestCaseReleaseYT("success case", testCase);
            assertEq(
                _term.totalSupply(assetId),
                testCase.totalSupply - testCase.amount,
                "unexpected totalSupply"
            );
        }
        if (
            _term.balanceOf(assetId, source) !=
            testCase.sourceBalance - testCase.amount
        ) {
            logTestCaseReleaseYT("success case", testCase);
            assertEq(
                _term.balanceOf(assetId, source),
                testCase.sourceBalance - testCase.amount,
                "unexpected sourceBalance"
            );
        }
        (uint128 shares, uint128 pt) = _term.yieldTerms(assetId);
        if (
            shares !=
            testCase.yieldState.shares -
                (testCase.yieldState.shares * testCase.amount) /
                testCase.totalSupply
        ) {
            logTestCaseReleaseYT("success case", testCase);
            assertEq(
                shares,
                testCase.yieldState.shares -
                    (testCase.yieldState.shares * testCase.amount) /
                    testCase.totalSupply,
                "unexpected yieldTerms[assetId].shares"
            );
        }
        if (
            pt !=
            testCase.yieldState.pt -
                (testCase.yieldState.pt * testCase.amount) /
                testCase.totalSupply
        ) {
            logTestCaseReleaseYT("success case", testCase);
            assertEq(
                pt,
                testCase.yieldState.pt -
                    (testCase.yieldState.pt * testCase.amount) /
                    testCase.totalSupply,
                "unexpected yieldTerms[assetId].pt"
            );
        }

        // A higher-level invariant that ensures that we're never giving YT
        // holders more value than exists in the contract.
        if (
            value >
            (testCase.currentPricePerShare * testCase.sharesPerExpiry) /
                _term.one()
        ) {
            logTestCaseReleaseYT("success case", testCase);
            assertFalse(
                value >
                    (testCase.currentPricePerShare * testCase.sharesPerExpiry) /
                        _term.one(),
                "unexpectedly high value"
            );
        }
    }

    function logTestCaseReleaseYT(
        string memory prelude,
        ReleaseYTTestCase memory testCase
    ) internal view {
        console.log(prelude);
        console.log("");
        console.log("    amount                   = ", testCase.amount);
        console.log(
            "    currentPricePerShare     = ",
            testCase.currentPricePerShare
        );
        console.log(
            "    finalState.pricePerShare = ",
            testCase.finalState.pricePerShare
        );
        console.log(
            "    finalState.interest      = ",
            testCase.finalState.interest
        );
        console.log(
            "    sharesPerExpiry          = ",
            testCase.sharesPerExpiry
        );
        console.log("    totalSupply              = ", testCase.totalSupply);
        console.log(
            "    sourceBalance              = ",
            testCase.sourceBalance
        );
        console.log(
            "    yieldState.shares        = ",
            testCase.yieldState.shares
        );
        console.log("    yieldState.pt            = ", testCase.yieldState.pt);
        console.log("");
    }

    // -------------------  _releasePT unit tests   ------------------ //

    function testCombinatorialReleasePT() public {
        // Get the test cases.
        uint256[] memory innerInputs = new uint256[](4);
        innerInputs[0] = 0;
        innerInputs[1] = 1 ether;
        innerInputs[2] = 2 ether;
        innerInputs[3] = 3.7435 ether;
        uint256[][] memory inputs = new uint256[][](6);
        for (uint256 i = 0; i < inputs.length; i++) {
            inputs[i] = innerInputs;
        }
        ReleasePTTestCase[] memory testCases = convertToReleasePTTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        // Set the address.
        startHoax(source);

        // Create an asset ID of a PT that expires at 10,000.
        uint256 assetId = Utils.encodeAssetId(false, 0, 10_000);

        for (uint256 i = 0; i < testCases.length; i++) {
            // Set up the test's state in the term contract.
            Term.FinalizedState memory finalState = Term.FinalizedState({
                pricePerShare: 0.1 ether,
                interest: testCases[i].interest
            });
            _term.setSharesPerExpiry(assetId, testCases[i].sharesPerExpiry);
            _term.setCurrentPricePerShare(testCases[i].currentPricePerShare);
            _term.setUserBalance(assetId, source, testCases[i].sourceBalance);
            _term.setTotalSupply(assetId, testCases[i].totalSupply);

            bytes memory expectedError = getExpectedErrorReleasePT(
                testCases[i]
            );
            if (expectedError.length > 0) {
                console.log("failure case ");
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
                    "    sourceBalance          = ",
                    testCases[i].sourceBalance
                );
                console.log("");

                vm.expectRevert(expectedError);
                _term.releasePTExternal(
                    finalState,
                    assetId,
                    source,
                    testCases[i].amount
                );
            } else {
                console.log("success case ");
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
                    "    sourceBalance          = ",
                    testCases[i].sourceBalance
                );
                console.log("");

                (uint256 shares, uint256 value) = _term.releasePTExternal(
                    finalState,
                    assetId,
                    source,
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
        // The source's balance of PT.
        uint256 sourceBalance;
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
                sourceBalance: rawTestCases[i][5]
            });
        }
    }

    // Given a test case, get the expected error that will be thrown by a failed
    // call to _releasePT.
    function getExpectedErrorReleasePT(ReleasePTTestCase memory testCase)
        internal
        view
        returns (bytes memory)
    {
        if (testCase.currentPricePerShare == 0) {
            return stdError.divisionError;
        } else if (
            (testCase.interest * _term.one()) / testCase.currentPricePerShare >
            testCase.sharesPerExpiry
        ) {
            // TODO: Re-evaluate this case in the context of _releaseYT.
            return stdError.arithmeticError;
        } else if (testCase.totalSupply == 0) {
            return stdError.divisionError;
        } else if (
            testCase.amount > testCase.sourceBalance ||
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
            (testCase.interest * _term.one()) /
            testCase.currentPricePerShare;
        uint256 expectedShares = (expectedPTShares * testCase.amount) /
            testCase.totalSupply;
        uint256 expectedValue = (expectedShares *
            testCase.currentPricePerShare) / _term.one();
        assertEq(shares, expectedShares);
        assertEq(value, expectedValue);

        // Ensure that the state was updated correctly.
        assertEq(
            _term.totalSupply(assetId),
            testCase.totalSupply - testCase.amount
        );
        assertEq(
            _term.balanceOf(assetId, source),
            testCase.sourceBalance - testCase.amount
        );
        assertEq(
            _term.sharesPerExpiry(assetId),
            testCase.sharesPerExpiry - expectedShares
        );
    }

    // ------------------- _parseAssetId unit tests ------------------ //

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
                    Utils.encodeAssetId(
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
                    Utils.encodeAssetId(
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
