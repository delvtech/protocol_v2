// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/mocks/MockTerm.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "test/Utils.sol";

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

    // -------------------  _releaseYT unit tests   ------------------ //

    function testCombinatorialReleaseYT() public {
        // Get the test cases. We're using inputs with lots of digits
        // since there aren't any failure cases relying on inputs being
        // multiples. We can only use three inputs since 4 ** 9 cases blows
        // over foundry's gas limit (TODO: Consider making a PR to Foundry to
        // make foundry's gas limit larger since executing this amount of test
        // cases is pretty reasonable from a time perspective).
        uint256[] memory inputs = new uint256[](3);
        inputs[0] = 0;
        inputs[1] = 1.8349 ether + 808324;
        inputs[2] = 2.2342 ether + 838903;
        ReleaseYTTestCase[] memory testCases = convertToReleaseYTTestCase(
            Utils.generateTestingMatrix(9, inputs)
        );

        // Set the address.
        startHoax(user);

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
            _term.setUnderlyingReturnValue(testCases[i].currentPricePerShare);
            _term.setUserBalance(assetId, user, testCases[i].userBalance);
            _term.setYieldState(assetId, testCases[i].yieldState);

            bytes memory expectedError = getExpectedErrorReleaseYT(
                testCases[i]
            );
            if (expectedError.length > 0) {
                try
                    _term.releaseYTExternal(
                        finalState,
                        assetId,
                        user,
                        testCases[i].amount
                    )
                {
                    logTestCaseReleaseYT("failure test case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (
                        keccak256(abi.encodePacked(error)) !=
                        keccak256(abi.encodePacked(expectedError))
                    ) {
                        logTestCaseReleaseYT("failure test case", testCases[i]);
                        assertEq(error, expectedError);
                    }
                }
            } else {
                try
                    _term.releaseYTExternal(
                        finalState,
                        assetId,
                        user,
                        testCases[i].amount
                    )
                returns (uint256 shares, uint256 value) {
                    validateReleaseYTSuccess(
                        testCases[i],
                        assetId,
                        shares,
                        value
                    );
                } catch {
                    logTestCaseReleaseYT("success test case", testCases[i]);
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
        // The balance of YT that the user will be given.
        uint256 userBalance;
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
                userBalance: rawTestCases[i][6],
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
        uint256 userInterest = (termEndingInterest * testCase.amount) /
            testCase.totalSupply;
        uint256 userShares = (userInterest * _term.one()) /
            testCase.currentPricePerShare;
        return (userShares, userInterest);
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
            uint256 userShares,
            uint256 userInterest
        ) = getExpectedReturnValuesReleaseYT(testCase);
        if (userShares > testCase.sharesPerExpiry) {
            return stdError.arithmeticError;
        } else if (userInterest > testCase.finalState.interest) {
            return stdError.arithmeticError;
        } else if (
            testCase.amount > testCase.userBalance ||
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
            logTestCaseReleaseYT("success test case", testCase);
            assertEq(shares, expectedShares, "unexpected shares");
        }
        if (value != expectedValue) {
            logTestCaseReleaseYT("success test case", testCase);
            assertEq(value, expectedValue, "unexpected value");
        }

        // Ensure that the state was updated correctly.
        (, , uint256 expiry) = _term.parseAssetIdExternal(assetId);
        (uint128 pricePerShare, uint128 interest) = _term.finalizedTerms(
            expiry
        );
        // TODO: These could be helper functions in Test.sol
        if (pricePerShare != testCase.finalState.pricePerShare) {
            logTestCaseReleaseYT("success test case", testCase);
            assertEq(
                pricePerShare,
                testCase.finalState.pricePerShare,
                "unexpected pricePerShare"
            );
        }
        if (interest != testCase.finalState.interest - expectedValue) {
            logTestCaseReleaseYT("success test case", testCase);
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
            logTestCaseReleaseYT("success test case", testCase);
            assertEq(
                _term.sharesPerExpiry(expiry),
                testCase.sharesPerExpiry - expectedShares,
                "unexpected sharesPerExpiry"
            );
        }
        if (
            _term.totalSupply(assetId) != testCase.totalSupply - testCase.amount
        ) {
            logTestCaseReleaseYT("success test case", testCase);
            assertEq(
                _term.totalSupply(assetId),
                testCase.totalSupply - testCase.amount,
                "unexpected totalSupply"
            );
        }
        if (
            _term.balanceOf(assetId, user) !=
            testCase.userBalance - testCase.amount
        ) {
            logTestCaseReleaseYT("success test case", testCase);
            assertEq(
                _term.balanceOf(assetId, user),
                testCase.userBalance - testCase.amount,
                "unexpected userBalance"
            );
        }
        (uint128 shares, uint128 pt) = _term.yieldTerms(assetId);
        if (
            shares !=
            testCase.yieldState.shares -
                (testCase.yieldState.shares * testCase.amount) /
                testCase.totalSupply
        ) {
            logTestCaseReleaseYT("success test case", testCase);
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
            logTestCaseReleaseYT("success test case", testCase);
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
            logTestCaseReleaseYT("success test case", testCase);
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
        console.log("    userBalance              = ", testCase.userBalance);
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
        uint256 assetId = Utils.encodeAssetId(false, 0, 10_000);

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
                try
                    _term.releasePTExternal(
                        finalState,
                        assetId,
                        user,
                        testCases[i].amount
                    )
                {
                    logTestCaseReleasePT("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (
                        keccak256(abi.encodePacked(error)) !=
                        keccak256(abi.encodePacked(expectedError))
                    ) {
                        logTestCaseReleasePT("failure case", testCases[i]);
                        assertEq(error, expectedError);
                    }
                }
            } else {
                try
                    _term.releasePTExternal(
                        finalState,
                        assetId,
                        user,
                        testCases[i].amount
                    )
                returns (uint256 shares, uint256 value) {
                    validateReleasePTSuccess(
                        testCases[i],
                        assetId,
                        shares,
                        value
                    );
                } catch {
                    logTestCaseReleasePT("success case", testCases[i]);
                    revert("fails unexpectedly");
                }
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
            (testCase.interest * _term.one()) /
            testCase.currentPricePerShare;
        uint256 expectedShares = (expectedPTShares * testCase.amount) /
            testCase.totalSupply;
        uint256 expectedValue = (expectedShares *
            testCase.currentPricePerShare) / 1e18;
        if (shares != expectedShares) {
            logTestCaseReleasePT("success case", testCase);
            assertEq(shares, expectedShares);
        }
        if (value != expectedValue) {
            logTestCaseReleasePT("success case", testCase);
            assertEq(value, expectedValue);
        }

        // Ensure that the state was updated correctly.
        if (
            _term.totalSupply(assetId) != testCase.totalSupply - testCase.amount
        ) {
            logReleasePTTestCase("success case", testCase);
            assertEq(
                _term.totalSupply(assetId),
                testCase.totalSupply - testCase.amount
            );
        }
        if (
            _term.balanceOf(assetId, user) !=
            testCase.userBalance - testCase.amount
        ) {
            logTestCaseReleasePT("success case", testCase);
            assertEq(
                _term.balanceOf(assetId, user),
                testCase.userBalance - testCase.amount
            );
        }
        if (
            _term.sharesPerExpiry(assetId) !=
            testCase.sharesPerExpiry - expectedShares
        ) {
            logTestCaseReleasePT("success case", testCase);
            assertEq(
                _term.sharesPerExpiry(assetId),
                testCase.sharesPerExpiry - expectedShares
            );
        }
    }

    function logTestCaseReleasePT(
        string memory prelude,
        ReleasePTTestCase memory testCase
    ) internal view {
        console.log(prelude);
        console.log("");
        console.log("    amount               = ", testCase.amount);
        console.log("    interest             = ", testCase.interest);
        console.log("    sharesPerExpiry      = ", testCase.sharesPerExpiry);
        console.log("    totalSupply          = ", testCase.totalSupply);
        console.log(
            "    currentPricePerShare = ",
            testCase.currentPricePerShare
        );
        console.log("    userBalance          = ", testCase.userBalance);
        console.log("");
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
