// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console2.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/interfaces/IYieldAdapter.sol";
import "contracts/libraries/Errors.sol";
import "contracts/mocks/MockTerm.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "test/ElementTest.sol";
import "test/Utils.sol";

contract TermUnitTest is ElementTest {
    address public destination = makeAddress("destination");
    address public source = makeAddress("source");

    ForwarderFactory internal _factory;
    MockTerm internal _term;
    MockERC20Permit internal _underlying;

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

    // ----------------------- mock events ----------------------- //

    event Convert(IYieldAdapter.ShareState shareState, uint256 shares);
    event CreateYT(
        address destination,
        uint256 value,
        uint256 totalShares,
        uint256 startTime,
        uint256 expiration
    );
    event Deposit(IYieldAdapter.ShareState shareState);
    event FinalizeTerm(uint256 expiry);
    event ReleaseAsset(uint256 assetId, address source, uint256 amount);
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
    event Transfer(address indexed from, address indexed to, uint256 value);
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );
    event Withdraw(
        uint256 shares,
        address destination,
        IYieldAdapter.ShareState shareState
    );

    // ------------------- lock ------------------- //

    struct LockTestCase {
        uint256[] assetIds;
        uint256[] amounts;
        uint256 createYTDiscountFactor;
        uint256 expiration;
        bool hasPreFunding;
        uint256 sharesToUnlockedShares;
        uint256 sourceBalance;
        uint256 underlyingAmount;
        uint256 ytBeginDate;
    }

    function testLock() public {
        vm.warp(5_000);
        startHoax(source);

        uint256[] memory assetIds = new uint256[](1);
        assetIds[
            0
        ] = 57896044618658097711785492504343953926634992332820282019728792003956564819968;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        LockTestCase memory testCase = LockTestCase({
            assetIds: assetIds,
            amounts: amounts,
            createYTDiscountFactor: 0,
            expiration: 10_000,
            hasPreFunding: false,
            sharesToUnlockedShares: 0,
            sourceBalance: 0,
            underlyingAmount: 0,
            ytBeginDate: 2500
        });

        _term.setSharesToUnlockedShare(testCase.sharesToUnlockedShares);
        _underlying.setBalance(source, testCase.sourceBalance);
        _underlying.approve(address(_term), type(uint256).max);

        (
            bool shouldExpectError,
            bytes memory expectedError
        ) = _getExpectedErrorLock(testCase);
        if (shouldExpectError) {
            _term.lockExternal(
                testCase.assetIds,
                testCase.amounts,
                testCase.underlyingAmount,
                testCase.hasPreFunding,
                destination,
                destination,
                testCase.ytBeginDate,
                testCase.expiration
            );
        } else {
            _validateLockSuccess(testCase);
        }
    }

    function testCombinatorialLock() public {
        vm.warp(5_000);
        startHoax(source);

        uint256[][] memory inputs = new uint256[][](9);
        // asset ids
        inputs[0] = new uint256[](7);
        inputs[0][0] = 0;
        inputs[0][1] = 1;
        inputs[0][2] = 2;
        inputs[0][3] = 3;
        inputs[0][4] = 4;
        inputs[0][5] = 5;
        inputs[0][6] = 6;
        // amounts
        inputs[1] = new uint256[](6);
        inputs[1][0] = 0;
        inputs[1][1] = 1;
        inputs[1][2] = 2;
        inputs[1][3] = 3;
        inputs[1][4] = 4;
        inputs[1][5] = 5;
        // createYTDiscountFactor
        inputs[2] = new uint256[](2);
        inputs[2][0] = 0;
        inputs[2][1] = 1 ether;
        // expiration
        inputs[3] = new uint256[](2);
        inputs[3][0] = block.timestamp / 2;
        inputs[3][1] = block.timestamp * 2;
        // hasPreFunding
        inputs[4] = new uint256[](2);
        inputs[4][0] = 0;
        inputs[4][1] = 1;
        // sharesToUnlockedShares
        inputs[5] = new uint256[](3);
        inputs[5][0] = 0;
        inputs[5][1] = 1 ether;
        inputs[5][2] = 3.7843 ether;
        // sourceBalance
        inputs[6] = new uint256[](3);
        inputs[6][0] = 0;
        inputs[6][1] = 1 ether;
        inputs[6][2] = 10 ether;
        // underlyingAmount
        inputs[7] = new uint256[](3);
        inputs[7][0] = 0;
        inputs[7][1] = 1.79345 ether + 123;
        inputs[7][2] = 4.87234 ether + 9721;
        // ytBeginDate
        inputs[8] = new uint256[](2);
        inputs[8][0] = block.timestamp / 2;
        inputs[8][1] = block.timestamp * 2;
        // generate testing matrix
        LockTestCase[] memory testCases = _convertToLockTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        _underlying.approve(address(_term), type(uint256).max);
        for (uint256 i = 0; i < testCases.length; i++) {
            _term.setSharesToUnlockedShare(testCases[i].sharesToUnlockedShares);
            _underlying.setBalance(source, testCases[i].sourceBalance);

            (
                bool shouldExpectError,
                bytes memory expectedError
            ) = _getExpectedErrorLock(testCases[i]);
            if (shouldExpectError) {
                _validateLockError(testCases[i], expectedError);
            } else {
                _validateLockSuccess(testCases[i]);
            }
        }
    }

    function _convertToLockTestCase(uint256[][] memory rawTestCases)
        internal
        view
        returns (LockTestCase[] memory testCases)
    {
        testCases = new LockTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 9,
                "Raw test case must have length of 9."
            );
            (
                uint256[] memory assetIds,
                uint256[] memory amounts
            ) = _getFixturesAssetIdsAndAmounts(
                    rawTestCases[i][0],
                    rawTestCases[i][1]
                );
            testCases[i] = LockTestCase({
                assetIds: assetIds,
                amounts: amounts,
                createYTDiscountFactor: rawTestCases[i][2],
                expiration: rawTestCases[i][3],
                hasPreFunding: rawTestCases[i][4] > 0 ? true : false,
                sharesToUnlockedShares: rawTestCases[i][5],
                sourceBalance: rawTestCases[i][6],
                underlyingAmount: rawTestCases[i][7],
                ytBeginDate: rawTestCases[i][8]
            });
        }
    }

    function _validateLockSuccess(LockTestCase memory testCase) internal {
        _registerExpectedEventsLock(testCase);
        try
            _term.lockExternal(
                testCase.assetIds,
                testCase.amounts,
                testCase.underlyingAmount,
                testCase.hasPreFunding,
                destination,
                destination,
                testCase.ytBeginDate,
                testCase.expiration
            )
        returns (uint256 ptCreated, uint256 ytCreated) {
            // FIXME: Validate state changes and return values.
        } catch {
            _logTestCaseLock("success case", testCase);
            revert("fails unexpectedly");
        }
    }

    function _registerExpectedEventsLock(LockTestCase memory testCase)
        internal
    {
        if (testCase.underlyingAmount > 0) {
            expectStrictEmit();
            emit Transfer(source, address(_term), testCase.underlyingAmount);
        }
        if (testCase.underlyingAmount > 0 || testCase.hasPreFunding) {
            expectStrictEmit();
            emit Deposit(IYieldAdapter.ShareState.Locked);
        }
        (
            uint256 totalValue,
            uint256 totalShares,
            uint256 ytBeginDate,
            uint256 discount
        ) = _getExpectedCalculationsLock(testCase);
        for (uint256 i = 0; i < testCase.assetIds.length; i++) {
            expectStrictEmit();
            emit ReleaseAsset(
                testCase.assetIds[i],
                source,
                testCase.amounts[i]
            );
            if (testCase.assetIds[i] == _term.UNLOCKED_YT_ID()) {
                expectStrictEmit();
                emit Convert(
                    IYieldAdapter.ShareState.Unlocked,
                    testCase.amounts[i]
                );
            }
        }
        expectStrictEmit();
        emit CreateYT(
            destination,
            totalValue,
            totalShares,
            ytBeginDate,
            testCase.expiration
        );
        if (totalValue - discount > 0) {
            expectStrictEmit();
            emit TransferSingle(
                source,
                address(0),
                destination,
                testCase.expiration,
                totalValue - discount
            );
        }
    }

    function _validateLockError(
        LockTestCase memory testCase,
        bytes memory expectedError
    ) internal {
        try
            _term.lockExternal(
                testCase.assetIds,
                testCase.amounts,
                testCase.underlyingAmount,
                testCase.hasPreFunding,
                destination,
                destination,
                testCase.ytBeginDate,
                testCase.expiration
            )
        {
            _logTestCaseLock("failure case", testCase);
            revert("succeeds unexpectedly");
        } catch (bytes memory error) {
            if (Utils.neq(error, expectedError)) {
                _logTestCaseLock("failure case", testCase);
                assertEq(error, expectedError);
            }
        }
    }

    function _getExpectedErrorLock(LockTestCase memory testCase)
        internal
        view
        returns (bool, bytes memory)
    {
        if (testCase.expiration <= block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermExpired.selector)
            );
        }
        if (testCase.underlyingAmount > testCase.sourceBalance) {
            return (true, encodeStringError("ERC20: insufficient-balance"));
        }
        if (testCase.assetIds.length > 0) {
            uint256 lastAssetId = 0;
            for (uint256 i = 0; i < testCase.assetIds.length; i++) {
                if (i >= testCase.amounts.length) {
                    return (true, stdError.indexOOBError);
                }
                if (lastAssetId >= testCase.assetIds[i]) {
                    return (
                        true,
                        abi.encodeWithSelector(
                            ElementError.UnsortedAssetIds.selector
                        )
                    );
                }
                lastAssetId = testCase.assetIds[i];
            }
        }
        (
            uint256 totalValue,
            ,
            ,
            uint256 discount
        ) = _getExpectedCalculationsLock(testCase);
        if (totalValue < discount) {
            return (true, stdError.arithmeticError);
        }
        return (false, new bytes(0));
    }

    function _getExpectedCalculationsLock(LockTestCase memory testCase)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 totalValue = 0;
        uint256 totalShares = 0;
        for (uint256 i = 0; i < testCase.assetIds.length; i++) {
            totalValue += testCase.amounts[i];
            if (testCase.assetIds[i] == _term.UNLOCKED_YT_ID()) {
                totalShares +=
                    (testCase.amounts[i] * testCase.sharesToUnlockedShares) /
                    _term.one();
            } else {
                totalShares += testCase.amounts[i];
            }
        }
        uint256 ytBeginDate = testCase.ytBeginDate >= block.timestamp
            ? block.timestamp
            : testCase.ytBeginDate;
        uint256 discount = (totalValue * testCase.createYTDiscountFactor) /
            _term.one();
        return (totalValue, totalShares, ytBeginDate, discount);
    }

    function _logTestCaseLock(
        string memory prelude,
        LockTestCase memory testCase
    ) internal view {
        console2.log(prelude);
        console2.log("");
        Utils.logArray("    assetIds: ", testCase.assetIds);
        Utils.logArray("    amounts: ", testCase.amounts);
        console2.log(
            "    createYTDiscountFactor: ",
            testCase.createYTDiscountFactor
        );
        console2.log("    expiration: ", testCase.expiration);
        console2.log("    hasPreFunding: ", testCase.hasPreFunding);
        console2.log(
            "    sharesToUnlockedShares: ",
            testCase.sharesToUnlockedShares
        );
        console2.log("    sourceBalance: ", testCase.sourceBalance);
        console2.log("    underlyingAmount: ", testCase.underlyingAmount);
        console2.log("    ytBeginDate: ", testCase.ytBeginDate);
        console2.log("");
    }

    // ------------------- depositUnlocked ------------------- //

    struct DepositUnlockedTestCase {
        uint256 depositReturnShares;
        uint256 depositReturnValue;
        uint256 ptAmount;
        uint256 ptExpiry;
        uint256 sharesToUnlockedShares;
        uint256 sourceBalance;
        uint256 underlyingAmount;
    }

    function testCombinatorialDepositUnlocked() public {
        vm.warp(5_000);
        startHoax(source);

        uint256[][] memory inputs = new uint256[][](7);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0;
        amounts[1] = 1.54893 ether + 234;
        amounts[2] = 3.34534 ether + 12;
        // deposit return shares
        inputs[0] = amounts;
        // deposit return value
        inputs[1] = amounts;
        // ptAmount
        inputs[2] = amounts;
        // ptExpiry
        inputs[3] = new uint256[](6);
        inputs[3][0] = 0;
        inputs[3][1] = block.timestamp;
        inputs[3][2] = block.timestamp * 2;
        inputs[3][3] = Utils.encodeAssetId(true, 0, 0);
        inputs[3][4] = Utils.encodeAssetId(false, 1, 0);
        inputs[3][5] = Utils.encodeAssetId(true, 1, 0);
        // shares to unlocked shares
        inputs[4] = amounts;
        // sourceBalance
        inputs[5] = amounts;
        // underlyingAmount
        inputs[6] = amounts;
        // generate test cases
        DepositUnlockedTestCase[]
            memory testCases = _convertToDepositUnlockedTestCase(
                Utils.generateTestingMatrix(inputs)
            );

        for (uint256 i = 0; i < testCases.length; i++) {
            _term.setSharesToUnlockedShare(testCases[i].sharesToUnlockedShares);
            _term.setDepositReturnValues(
                testCases[i].depositReturnShares,
                testCases[i].depositReturnValue
            );
            _underlying.mint(source, testCases[i].sourceBalance);

            (
                bool shouldExpectError,
                bytes memory expectedError
            ) = _getExpectedErrorDepositUnlocked(testCases[i]);
            if (shouldExpectError) {
                try
                    _term.depositUnlockedExternal(
                        testCases[i].underlyingAmount,
                        testCases[i].ptAmount,
                        testCases[i].ptExpiry,
                        destination
                    )
                {
                    _logTestCaseDepositUnlocked("failure case", testCases[i]);
                    revert("succeeds unexpectedly");
                } catch (bytes memory error) {
                    if (Utils.neq(error, expectedError)) {
                        _logTestCaseDepositUnlocked(
                            "failure case",
                            testCases[i]
                        );
                        assertEq(error, expectedError);
                    }
                }
            } else {
                _registerExpectedEventsDepositUnlocked(testCases[i]);
                try
                    _term.depositUnlockedExternal(
                        testCases[i].underlyingAmount,
                        testCases[i].ptAmount,
                        testCases[i].ptExpiry,
                        destination
                    )
                returns (uint256 value, uint256 shares) {
                    _validateSuccessDepositUnlocked(
                        testCases[i],
                        value,
                        shares
                    );
                } catch {
                    _logTestCaseDepositUnlocked("success case", testCases[i]);
                    revert("fails unexpectedly");
                }
            }
        }
    }

    function _convertToDepositUnlockedTestCase(uint256[][] memory rawTestMatrix)
        internal
        pure
        returns (DepositUnlockedTestCase[] memory)
    {
        DepositUnlockedTestCase[] memory result = new DepositUnlockedTestCase[](
            rawTestMatrix.length
        );
        for (uint256 i = 0; i < rawTestMatrix.length; i++) {
            _validateTestCaseLength(rawTestMatrix[i], 7);
            result[i] = DepositUnlockedTestCase({
                depositReturnShares: rawTestMatrix[i][0],
                depositReturnValue: rawTestMatrix[i][1],
                ptAmount: rawTestMatrix[i][2],
                ptExpiry: rawTestMatrix[i][3],
                sharesToUnlockedShares: rawTestMatrix[i][4],
                sourceBalance: rawTestMatrix[i][5],
                underlyingAmount: rawTestMatrix[i][6]
            });
        }
        return result;
    }

    function _registerExpectedEventsDepositUnlocked(
        DepositUnlockedTestCase memory testCase
    ) internal {
        if (testCase.underlyingAmount > 0) {
            expectStrictEmit();
            emit Transfer(source, address(_term), testCase.underlyingAmount);
        }
        expectStrictEmit();
        emit Deposit(IYieldAdapter.ShareState.Unlocked);
        if (testCase.ptAmount > 0) {
            expectStrictEmit();
            emit ReleaseAsset(testCase.ptExpiry, source, testCase.ptAmount);
            expectStrictEmit();
            emit Convert(IYieldAdapter.ShareState.Locked, testCase.ptAmount);
        }
        (
            uint256 expectedShares,
            uint256 expectedValue
        ) = _getExpectedCalculationsDepositUnlocked(testCase);
        expectStrictEmit();
        emit CreateYT(destination, expectedValue, expectedShares, 0, 0);
    }

    function _validateSuccessDepositUnlocked(
        DepositUnlockedTestCase memory testCase,
        uint256 value,
        uint256 shares
    ) internal {
        uint256 sourceBalance = _underlying.balanceOf(source);
        if (
            sourceBalance != testCase.sourceBalance - testCase.underlyingAmount
        ) {
            _logTestCaseDepositUnlocked("success case", testCase);
            assertEq(
                sourceBalance,
                testCase.sourceBalance - testCase.underlyingAmount,
                "unexpected source balance"
            );
        }
        (
            uint256 expectedShares,
            uint256 expectedValue
        ) = _getExpectedCalculationsDepositUnlocked(testCase);
        if (shares != expectedShares) {
            _logTestCaseDepositUnlocked("success case", testCase);
            assertEq(shares, expectedShares, "unexpected shares");
        }
        if (value != expectedValue) {
            _logTestCaseDepositUnlocked("success case", testCase);
            assertEq(value, expectedValue, "unexpected value");
        }
    }

    function _getExpectedCalculationsDepositUnlocked(
        DepositUnlockedTestCase memory testCase
    ) internal view returns (uint256, uint256) {
        uint256 expectedShares = testCase.depositReturnShares;
        uint256 expectedValue = testCase.depositReturnValue;
        if (testCase.ptAmount > 0) {
            expectedShares +=
                (testCase.ptAmount * testCase.sharesToUnlockedShares) /
                _term.one();
            expectedValue += testCase.ptAmount;
        }
        return (expectedShares, expectedValue);
    }

    function _getExpectedErrorDepositUnlocked(
        DepositUnlockedTestCase memory testCase
    ) internal view returns (bool, bytes memory) {
        if (testCase.sourceBalance < testCase.underlyingAmount) {
            return (true, stdError.arithmeticError);
        }
        if (testCase.ptExpiry >= block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermExpired.selector)
            );
        }
        return (false, new bytes(0));
    }

    function _logTestCaseDepositUnlocked(
        string memory prelude,
        DepositUnlockedTestCase memory testCase
    ) internal view {
        console2.log(prelude);
        console2.log("");
        console2.log("    depositReturnShares: ", testCase.depositReturnShares);
        console2.log("    depositReturnValue: ", testCase.depositReturnValue);
        console2.log("    ptAmount: ", testCase.ptAmount);
        console2.log("    ptExpiry: ", testCase.ptExpiry);
        console2.log(
            "    sharesToUnlockedShares: ",
            testCase.sharesToUnlockedShares
        );
        console2.log("    sourceBalance: ", testCase.sourceBalance);
        console2.log("    underlyingAmount: ", testCase.underlyingAmount);
        console2.log("");
    }

    // ------------------- unlock unit tests ------------------- //

    function testCombinatorialUnlock() public {
        startHoax(source);

        uint256[][] memory inputs = new uint256[][](4);
        // asset ids
        inputs[0] = new uint256[](7);
        inputs[0][0] = 0;
        inputs[0][1] = 1;
        inputs[0][2] = 2;
        inputs[0][3] = 3;
        inputs[0][4] = 4;
        inputs[0][5] = 5;
        inputs[0][6] = 6;
        // amounts
        inputs[1] = new uint256[](6);
        inputs[1][0] = 0;
        inputs[1][1] = 1;
        inputs[1][2] = 2;
        inputs[1][3] = 3;
        inputs[1][4] = 4;
        inputs[1][5] = 5;
        // current price per share
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0;
        amounts[1] = 1.8345 ether + 234234;
        amounts[2] = 17.3453 ether + 345345;
        inputs[2] = amounts;
        inputs[3] = amounts;
        // generate the test cases
        UnlockTestCase[] memory testCases = _convertToUnlockTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        for (uint256 i = 0; i < testCases.length; i++) {
            _term.setCurrentPricePerShare(
                testCases[i].currentPricePerShareLocked,
                IYieldAdapter.ShareState.Locked
            );
            _term.setCurrentPricePerShare(
                testCases[i].currentPricePerShareUnlocked,
                IYieldAdapter.ShareState.Unlocked
            );

            (
                bool shouldExpectError,
                bytes memory expectedError
            ) = _getExpectedErrorUnlock(testCases[i]);
            if (shouldExpectError) {
                try
                    _term.unlockExternal(
                        destination,
                        testCases[i].assetIds,
                        testCases[i].amounts
                    )
                {
                    _logTestCaseUnlock("failure case", testCases[i]);
                    revert("succeeds unexpectedly");
                } catch (bytes memory error) {
                    if (Utils.neq(error, expectedError)) {
                        _logTestCaseUnlock("failure case", testCases[i]);
                        assertEq(error, expectedError);
                    }
                }
            } else {
                _registerExpectedEventsUnlock(testCases[i]);
                try
                    _term.unlockExternal(
                        destination,
                        testCases[i].assetIds,
                        testCases[i].amounts
                    )
                returns (uint256 underlyingUnlocked) {
                    _validateSuccessUnlock(testCases[i], underlyingUnlocked);
                } catch {
                    _logTestCaseUnlock("success case", testCases[i]);
                    revert("fails unexpectedly");
                }
            }
        }
    }

    struct UnlockTestCase {
        uint256[] assetIds;
        uint256[] amounts;
        uint256 currentPricePerShareLocked;
        uint256 currentPricePerShareUnlocked;
    }

    function _convertToUnlockTestCase(uint256[][] memory rawTestCases)
        internal
        view
        returns (UnlockTestCase[] memory testCases)
    {
        testCases = new UnlockTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 4,
                "Raw test case must have length of 4."
            );
            (
                uint256[] memory assetIds,
                uint256[] memory amounts
            ) = _getFixturesAssetIdsAndAmounts(
                    rawTestCases[i][0],
                    rawTestCases[i][1]
                );
            testCases[i] = UnlockTestCase({
                assetIds: assetIds,
                amounts: amounts,
                currentPricePerShareLocked: rawTestCases[i][2],
                currentPricePerShareUnlocked: rawTestCases[i][3]
            });
        }
    }

    function _getExpectedErrorUnlock(UnlockTestCase memory testCase)
        internal
        pure
        returns (bool, bytes memory)
    {
        if (testCase.assetIds.length > 0) {
            uint256 lastAssetId = 0;
            for (uint256 i = 0; i < testCase.assetIds.length; i++) {
                if (lastAssetId >= testCase.assetIds[i]) {
                    return (
                        true,
                        abi.encodeWithSelector(
                            ElementError.UnsortedAssetIds.selector
                        )
                    );
                }
                if (i >= testCase.amounts.length) {
                    return (true, stdError.indexOOBError);
                }
                lastAssetId = testCase.assetIds[i];
            }
        }
        return (false, new bytes(0));
    }

    function _registerExpectedEventsUnlock(UnlockTestCase memory testCase)
        internal
    {
        uint256 expectedReleasedSharesUnlocked = 0;
        uint256 expectedReleasedSharesLocked = 0;
        for (uint256 i = 0; i < testCase.assetIds.length; i++) {
            expectStrictEmit();
            emit ReleaseAsset(
                testCase.assetIds[i],
                source,
                testCase.amounts[i]
            );
            if (testCase.assetIds[i] == _term.UNLOCKED_YT_ID()) {
                expectedReleasedSharesUnlocked += testCase.amounts[i];
            } else {
                expectedReleasedSharesLocked += testCase.amounts[i];
            }
        }
        if (expectedReleasedSharesLocked > 0) {
            expectStrictEmit();
            emit Withdraw(
                expectedReleasedSharesLocked,
                destination,
                IYieldAdapter.ShareState.Locked
            );
        }
        if (expectedReleasedSharesUnlocked > 0) {
            expectStrictEmit();
            emit Withdraw(
                expectedReleasedSharesUnlocked,
                destination,
                IYieldAdapter.ShareState.Unlocked
            );
        }
    }

    function _validateSuccessUnlock(
        UnlockTestCase memory testCase,
        uint256 underlyingUnlocked
    ) internal {
        uint256 expectedReleasedSharesLocked = 0;
        uint256 expectedReleasedSharesUnlocked = 0;
        for (uint256 i = 0; i < testCase.assetIds.length; i++) {
            if (testCase.assetIds[i] == _term.UNLOCKED_YT_ID()) {
                expectedReleasedSharesUnlocked += testCase.amounts[i];
            } else {
                expectedReleasedSharesLocked += testCase.amounts[i];
            }
        }
        uint256 expectedUnderlyingUnlocked = (expectedReleasedSharesLocked *
            testCase.currentPricePerShareLocked) /
            _term.one() +
            (expectedReleasedSharesUnlocked *
                testCase.currentPricePerShareUnlocked) /
            _term.one();
        if (underlyingUnlocked != expectedUnderlyingUnlocked) {
            _logTestCaseUnlock("success case", testCase);
            assertEq(underlyingUnlocked, expectedUnderlyingUnlocked);
        }
    }

    function _logTestCaseUnlock(
        string memory prelude,
        UnlockTestCase memory testCase
    ) internal view {
        console2.log(prelude);
        console2.log("");
        Utils.logArray("    assetIds: ", testCase.assetIds);
        Utils.logArray("    amounts: ", testCase.amounts);
        console2.log(
            "    currentPricePerShareLocked:",
            testCase.currentPricePerShareLocked
        );
        console2.log(
            "    currentPricePerShareUnlocked:",
            testCase.currentPricePerShareUnlocked
        );
        console2.log("");
    }

    // ------------------- unlockedSharePrice unit tests ------------------- //

    function testUnlockedSharePrice() public {
        uint256[] memory sharePrices = new uint256[](3);
        sharePrices[0] = 0;
        sharePrices[1] = 1 ether;
        sharePrices[2] = 2.2345 ether;

        for (uint256 i = 0; i < sharePrices.length; i++) {
            _term.setCurrentPricePerShare(
                sharePrices[i],
                IYieldAdapter.ShareState.Unlocked
            );

            uint256 unlockedSharePrice = _term.unlockedSharePrice();
            assertEq(unlockedSharePrice, sharePrices[i]);
        }
    }

    // ------------------- _createYT unit tests  ------------------ //

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
        CreateYTTestCase[] memory testCases = _convertToCreateYTTestCase(
            Utils.generateTestingMatrix(inputs)
        );

        for (uint256 i = 0; i < testCases.length; i++) {
            // Filter out pathological cases. If the expiration is
            // zero, the start time will always be zero.
            if (testCases[i].startTime != 0 && testCases[i].expiration == 0) {
                continue;
            }

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

            (
                bool shouldExpectError,
                bytes memory expectedError
            ) = _getExpectedErrorCreateYT(testCases[i]);
            if (shouldExpectError) {
                try
                    _term.createYTExternal(
                        destination,
                        testCases[i].value,
                        testCases[i].totalShares,
                        testCases[i].startTime,
                        testCases[i].expiration
                    )
                {
                    _logTestCaseCreateYT("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (Utils.neq(error, expectedError)) {
                        _logTestCaseCreateYT("failure case", testCases[i]);
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
                    _validateSuccessCreateYT(testCases[i], amount);
                } catch {
                    _logTestCaseCreateYT("success case", testCases[i]);
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

    function _convertToCreateYTTestCase(uint256[][] memory rawTestMatrix)
        internal
        pure
        returns (CreateYTTestCase[] memory)
    {
        CreateYTTestCase[] memory result = new CreateYTTestCase[](
            rawTestMatrix.length
        );
        for (uint256 i = 0; i < rawTestMatrix.length; i++) {
            _validateTestCaseLength(rawTestMatrix[i], 7);
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

    function _getExpectedErrorCreateYT(CreateYTTestCase memory testCase)
        internal
        view
        returns (bool, bytes memory)
    {
        if (testCase.expiration != 0 && testCase.startTime != block.timestamp) {
            if (
                testCase.yieldState.shares == 0 || testCase.yieldState.pt == 0
            ) {
                return (
                    true,
                    abi.encodeWithSelector(
                        ElementError.TermNotInitialized.selector
                    )
                );
            }
            if (testCase.totalShares == 0) {
                return (true, stdError.divisionError);
            }
            uint256 expectedImpliedShareValue = (testCase.yieldState.shares *
                testCase.value) / testCase.totalShares;
            if (expectedImpliedShareValue < uint256(testCase.yieldState.pt)) {
                return (true, stdError.arithmeticError);
            }
            if (testCase.totalSupply == 0) {
                return (true, stdError.divisionError);
            }
            uint256 expectedInterestEarned = expectedImpliedShareValue -
                testCase.yieldState.pt;
            uint256 expectedTotalDiscount = (testCase.value *
                expectedInterestEarned) / testCase.totalSupply;
            if (expectedTotalDiscount > testCase.totalShares) {
                return (true, stdError.arithmeticError);
            }
            if (expectedTotalDiscount > testCase.value) {
                return (true, stdError.arithmeticError);
            }
        }
        return (false, new bytes(0));
    }

    function _validateSuccessCreateYT(
        CreateYTTestCase memory testCase,
        uint256 amount
    ) internal {
        if (testCase.expiration == 0) {
            uint256 assetId = _term.UNLOCKED_YT_ID();
            if (amount != testCase.value) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(amount, testCase.value, "unexpected value");
            }
            uint256 balance = _term.balanceOf(assetId, destination);
            if (balance != testCase.totalShares) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(
                    balance,
                    testCase.totalShares,
                    "unexpected destination balance"
                );
            }
            uint256 totalSupply = _term.totalSupply(assetId);
            if (totalSupply != testCase.totalSupply + testCase.totalShares) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(
                    totalSupply,
                    testCase.totalSupply + testCase.totalShares,
                    "unexpected total supply"
                );
            }
            (uint256 shares, uint256 pt) = _term.yieldTerms(assetId);
            if (shares != testCase.yieldState.shares + testCase.totalShares) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(
                    shares,
                    testCase.yieldState.shares + testCase.totalShares,
                    "unexpected yieldState.shares"
                );
            }
            if (pt != testCase.yieldState.pt) {
                _logTestCaseCreateYT("success case", testCase);
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
                _logTestCaseCreateYT("success case", testCase);
                assertEq(amount, 0, "unexpected value");
            }
            uint256 balance = _term.balanceOf(assetId, destination);
            if (balance != testCase.value) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(
                    balance,
                    testCase.value,
                    "unexpected destination balance"
                );
            }
            uint256 totalSupply = _term.totalSupply(assetId);
            if (totalSupply != testCase.totalSupply + testCase.value) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(
                    totalSupply,
                    testCase.totalSupply + testCase.value,
                    "unexpected total supply"
                );
            }
            (uint256 shares, uint256 pt) = _term.yieldTerms(assetId);
            if (shares != testCase.yieldState.shares + testCase.totalShares) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(
                    shares,
                    testCase.yieldState.shares + testCase.totalShares,
                    "unexpected yieldState.shares"
                );
            }
            if (pt != testCase.yieldState.pt + testCase.value) {
                _logTestCaseCreateYT("success case", testCase);
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
            uint256 expectedImpliedShareValue = (testCase.yieldState.shares *
                testCase.value) / testCase.totalShares;
            uint256 expectedInterestEarned = expectedImpliedShareValue -
                testCase.yieldState.pt;
            uint256 expectedTotalDiscount = (testCase.value *
                expectedInterestEarned) / testCase.totalSupply;
            if (amount != expectedTotalDiscount) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(amount, expectedTotalDiscount, "unexpected amount");
            }
            uint256 balance = _term.balanceOf(assetId, destination);
            if (balance != testCase.value) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(balance, testCase.value, "unexpected balance");
            }
            uint256 totalSupply = _term.totalSupply(assetId);
            if (totalSupply != testCase.totalSupply + testCase.value) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(
                    totalSupply,
                    testCase.totalSupply + testCase.value,
                    "unexpected total supply"
                );
            }
            (uint256 shares, uint256 pt) = _term.yieldTerms(assetId);
            if (shares != testCase.yieldState.shares + testCase.totalShares) {
                _logTestCaseCreateYT("success case", testCase);
                assertEq(
                    shares,
                    testCase.yieldState.shares + testCase.totalShares,
                    "unexpected yieldState.shares"
                );
            }
            if (
                pt !=
                testCase.yieldState.pt + testCase.value - expectedTotalDiscount
            ) {
                _logTestCaseCreateYT("success case", testCase);
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

    function _logTestCaseCreateYT(
        string memory prelude,
        CreateYTTestCase memory testCase
    ) internal view {
        console2.log(prelude);
        console2.log("");
        console2.log("    value             = ", testCase.value);
        console2.log("    totalShares       = ", testCase.totalShares);
        console2.log("    startTime         = ", testCase.startTime);
        console2.log("    expiration        = ", testCase.expiration);
        console2.log("    yieldState.shares = ", testCase.yieldState.shares);
        console2.log("    yieldState.pt     = ", testCase.yieldState.pt);
        console2.log("    totalSupply       = ", testCase.totalSupply);
        console2.log("");
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
        ReleaseAssetTestCase[]
            memory testCases = _convertToReleaseAssetTestCase(
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

            (
                bool shouldExpectError,
                bytes memory expectedError
            ) = _getExpectedErrorReleaseAsset(testCases[i]);
            if (shouldExpectError) {
                try
                    _term.releaseAssetExternal(
                        testCases[i].assetId,
                        source,
                        testCases[i].amount
                    )
                {
                    _logTestCaseReleaseAsset("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (Utils.neq(error, expectedError)) {
                        _logTestCaseReleaseAsset("failure case", testCases[i]);
                        assertEq(error, expectedError);
                    }
                }
            } else {
                _registerExpectedEventsReleaseAsset(testCases[i]);
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
                } catch {
                    _logTestCaseReleaseAsset("success case", testCases[i]);
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

    function _convertToReleaseAssetTestCase(uint256[][] memory rawTestMatrix)
        internal
        pure
        returns (ReleaseAssetTestCase[] memory)
    {
        ReleaseAssetTestCase[] memory result = new ReleaseAssetTestCase[](
            rawTestMatrix.length
        );
        for (uint256 i = 0; i < rawTestMatrix.length; i++) {
            _validateTestCaseLength(rawTestMatrix[i], 3);
            result[i] = ReleaseAssetTestCase({
                amount: rawTestMatrix[i][0],
                assetId: rawTestMatrix[i][1],
                interest: uint128(rawTestMatrix[i][2])
            });
        }
        return result;
    }

    function _getExpectedErrorReleaseAsset(ReleaseAssetTestCase memory testCase)
        internal
        view
        returns (bool, bytes memory)
    {
        (, , uint256 expiry) = _term.parseAssetIdExternal(testCase.assetId);
        if (expiry > 5_000 && expiry != 0) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermNotExpired.selector)
            );
        }
        return (false, new bytes(0));
    }

    function _registerExpectedEventsReleaseAsset(
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

    function _logTestCaseReleaseAsset(
        string memory prelude,
        ReleaseAssetTestCase memory testCase
    ) internal view {
        console2.log(prelude);
        console2.log("");
        console2.log("    amount   = ", testCase.amount);
        console2.log("    assetId  = ", testCase.assetId);
        console2.log("    interest = ", testCase.interest);
        console2.log("");
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
        FinalizeTermTestCase[]
            memory testCases = _convertToFinalizeTermTestCase(
                Utils.generateTestingMatrix(inputs)
            );

        // Set the address.
        startHoax(source);

        // We pick a fixed expiry since it wouldn't effect the testing to
        // simulate different values for the parameter.
        uint256 expiry = 10_000;

        for (uint256 i = 0; i < testCases.length; i++) {
            // Set up the test state.
            _term.setCurrentPricePerShare(
                testCases[i].currentPricePerShare,
                IYieldAdapter.ShareState.Locked
            );
            _term.setSharesPerExpiry(expiry, testCases[i].sharesPerExpiry);
            _term.setTotalSupply(expiry, testCases[i].totalSupply);

            (
                bool shouldExpectError,
                bytes memory expectedError
            ) = _getExpectedErrorFinalizeTerm(testCases[i]);
            if (shouldExpectError) {
                try _term.finalizeTermExternal(expiry) {
                    _logTestCaseFinalizeTerm("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (Utils.neq(error, expectedError)) {
                        _logTestCaseFinalizeTerm("failure case", testCases[i]);
                        assertEq(error, expectedError);
                    }
                }
            } else {
                try _term.finalizeTermExternal(expiry) returns (
                    Term.FinalizedState memory finalState
                ) {
                    _validateSuccessFinalizeTerm(
                        testCases[i],
                        finalState,
                        expiry
                    );
                } catch {
                    _logTestCaseFinalizeTerm("success case", testCases[i]);
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

    function _convertToFinalizeTermTestCase(uint256[][] memory rawTestMatrix)
        internal
        pure
        returns (FinalizeTermTestCase[] memory)
    {
        FinalizeTermTestCase[] memory result = new FinalizeTermTestCase[](
            rawTestMatrix.length
        );
        for (uint256 i = 0; i < rawTestMatrix.length; i++) {
            _validateTestCaseLength(rawTestMatrix[i], 3);
            result[i] = FinalizeTermTestCase({
                currentPricePerShare: rawTestMatrix[i][0],
                sharesPerExpiry: rawTestMatrix[i][1],
                totalSupply: rawTestMatrix[i][2]
            });
        }
        return result;
    }

    function _getExpectedErrorFinalizeTerm(FinalizeTermTestCase memory testCase)
        internal
        pure
        returns (bool, bytes memory)
    {
        if (testCase.sharesPerExpiry == 0) {
            return (true, stdError.divisionError);
        }
        return (false, new bytes(0));
    }

    function _validateSuccessFinalizeTerm(
        FinalizeTermTestCase memory testCase,
        Term.FinalizedState memory finalState,
        uint256 expiry
    ) internal {
        // Ensure that the return value is correct.
        uint256 expectedPricePerShare = testCase.currentPricePerShare;
        if (
            stdMath.delta(finalState.pricePerShare, expectedPricePerShare) > 1
        ) {
            _logTestCaseFinalizeTerm("success case", testCase);
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
            _logTestCaseFinalizeTerm("success case", testCase);
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
            _logTestCaseFinalizeTerm("success case", testCase);
            assertApproxEqAbs(
                pricePerShare,
                expectedPricePerShare,
                1,
                "unexpected pricePerShare in state"
            );
        }
        if (interest != expectedInterest) {
            _logTestCaseFinalizeTerm("success case", testCase);
            assertEq(
                interest,
                expectedInterest,
                "unexpected interest in state"
            );
        }
    }

    function _logTestCaseFinalizeTerm(
        string memory prelude,
        FinalizeTermTestCase memory testCase
    ) internal view {
        console2.log(prelude);
        console2.log("");
        console2.log(
            "    currentPricePerShare =",
            testCase.currentPricePerShare
        );
        console2.log("    sharesPerExpiry      =", testCase.sharesPerExpiry);
        console2.log("    totalSupply          =", testCase.totalSupply);
        console2.log("");
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
            memory testCases = _convertToReleaseUnlockedTestCase(
                Utils.generateTestingMatrix(inputs)
            );

        // Set the address.
        startHoax(source);

        uint256 unlockedYTId = _term.UNLOCKED_YT_ID();
        for (uint256 i = 0; i < testCases.length; i++) {
            // Set up the test state.
            _term.setCurrentPricePerShare(
                testCases[i].currentPricePerShare,
                IYieldAdapter.ShareState.Unlocked
            );
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

            (
                bool shouldExpectError,
                bytes memory expectedError
            ) = _getExpectedErrorReleaseUnlocked(testCases[i]);
            if (shouldExpectError) {
                try _term.releaseUnlockedExternal(source, testCases[i].amount) {
                    _logTestCaseReleaseUnlocked("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (Utils.neq(error, expectedError)) {
                        _logTestCaseReleaseUnlocked(
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
                    _validateSuccessReleaseUnlocked(
                        testCases[i],
                        shares,
                        value
                    );
                } catch {
                    _logTestCaseReleaseUnlocked("success case", testCases[i]);
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

    function _convertToReleaseUnlockedTestCase(uint256[][] memory rawTestMatrix)
        internal
        pure
        returns (ReleaseUnlockedTestCase[] memory)
    {
        ReleaseUnlockedTestCase[] memory result = new ReleaseUnlockedTestCase[](
            rawTestMatrix.length
        );
        for (uint256 i = 0; i < rawTestMatrix.length; i++) {
            _validateTestCaseLength(rawTestMatrix[i], 5);
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

    function _getExpectedErrorReleaseUnlocked(
        ReleaseUnlockedTestCase memory testCase
    ) internal pure returns (bool, bytes memory) {
        if (testCase.totalSupply == 0) {
            return (true, stdError.divisionError);
        } else if (
            testCase.amount > testCase.totalSupply ||
            testCase.amount > testCase.sourceBalance
        ) {
            return (true, stdError.arithmeticError);
        }
        return (false, new bytes(0));
    }

    function _validateSuccessReleaseUnlocked(
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
            _logTestCaseReleaseUnlocked("success case", testCase);
            assertEq(shares, expectedShares, "unexpected shares");
        }
        if (value != expectedValue) {
            _logTestCaseReleaseUnlocked("success case", testCase);
            assertEq(value, expectedValue, "unexpected value");
        }

        // Ensure that the state was updated correctly.
        uint256 unlockedYTId = _term.UNLOCKED_YT_ID();
        uint256 totalSupply = _term.totalSupply(unlockedYTId);
        uint256 sourceBalance = _term.balanceOf(unlockedYTId, source);
        if (totalSupply != testCase.totalSupply - testCase.amount) {
            _logTestCaseReleaseUnlocked("success case", testCase);
            assertEq(
                totalSupply,
                testCase.totalSupply - testCase.amount,
                "unexpected totalSupply"
            );
        }
        if (sourceBalance != testCase.sourceBalance - testCase.amount) {
            _logTestCaseReleaseUnlocked("success case", testCase);
            assertEq(
                sourceBalance,
                testCase.sourceBalance - testCase.amount,
                "unexpected sourceBalance"
            );
        }
        (uint128 shares_, ) = _term.yieldTerms(unlockedYTId);
        if (shares_ != testCase.shares - expectedShares) {
            _logTestCaseReleaseUnlocked("success case", testCase);
            assertEq(
                shares_,
                testCase.shares - expectedShares,
                "unexpected shares"
            );
        }
    }

    function _logTestCaseReleaseUnlocked(
        string memory prelude,
        ReleaseUnlockedTestCase memory testCase
    ) internal view {
        console2.log(prelude);
        console2.log("");
        console2.log("    amount = ", testCase.amount);
        console2.log(
            "    currentPricePerShare = ",
            testCase.currentPricePerShare
        );
        console2.log("    shares               = ", testCase.shares);
        console2.log("    totalSupply          = ", testCase.totalSupply);
        console2.log("    sourceBalance          = ", testCase.sourceBalance);
        console2.log("");
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
        ReleaseYTTestCase[] memory testCases = _convertToReleaseYTTestCase(
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
            _term.setCurrentPricePerShare(
                testCases[i].currentPricePerShare,
                IYieldAdapter.ShareState.Locked
            );
            _term.setUserBalance(assetId, source, testCases[i].sourceBalance);
            _term.setYieldState(assetId, testCases[i].yieldState);

            (
                bool shouldExpectError,
                bytes memory expectedError
            ) = _getExpectedErrorReleaseYT(testCases[i]);
            if (shouldExpectError) {
                try
                    _term.releaseYTExternal(
                        finalState,
                        assetId,
                        source,
                        testCases[i].amount
                    )
                {
                    _logTestCaseReleaseYT("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (Utils.neq(error, expectedError)) {
                        _logTestCaseReleaseYT("failure case", testCases[i]);
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
                    _validateSuccessReleaseYT(
                        testCases[i],
                        assetId,
                        shares,
                        value
                    );
                } catch {
                    _logTestCaseReleaseYT("success case", testCases[i]);
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
    function _convertToReleaseYTTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (ReleaseYTTestCase[] memory testCases)
    {
        testCases = new ReleaseYTTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            _validateTestCaseLength(rawTestCases[i], 9);
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

    function _getExpectedReturnValuesReleaseYT(
        ReleaseYTTestCase memory testCase
    ) internal view returns (uint256, uint256) {
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
    function _getExpectedErrorReleaseYT(ReleaseYTTestCase memory testCase)
        internal
        view
        returns (bool, bytes memory)
    {
        if (testCase.totalSupply == 0) {
            return (true, stdError.divisionError);
        } else if (testCase.currentPricePerShare == 0) {
            return (true, stdError.divisionError);
        }
        (
            uint256 sourceShares,
            uint256 sourceInterest
        ) = _getExpectedReturnValuesReleaseYT(testCase);
        if (sourceShares > testCase.sharesPerExpiry) {
            return (true, stdError.arithmeticError);
        } else if (sourceInterest > testCase.finalState.interest) {
            return (true, stdError.arithmeticError);
        } else if (
            testCase.amount > testCase.sourceBalance ||
            testCase.amount > testCase.totalSupply
        ) {
            return (true, stdError.arithmeticError);
        }
        return (false, new bytes(0));
    }

    // Given a test case, validate the state transitions and return values of a
    // successful call to _releaseYT.
    function _validateSuccessReleaseYT(
        ReleaseYTTestCase memory testCase,
        uint256 assetId,
        uint256 shares,
        uint256 value
    ) internal {
        // Ensure that the calculated shares and value are correct.
        (
            uint256 expectedShares,
            uint256 expectedValue
        ) = _getExpectedReturnValuesReleaseYT(testCase);
        if (shares != expectedShares) {
            _logTestCaseReleaseYT("success case", testCase);
            assertEq(shares, expectedShares, "unexpected shares");
        }
        if (value != expectedValue) {
            _logTestCaseReleaseYT("success case", testCase);
            assertEq(value, expectedValue, "unexpected value");
        }

        // Ensure that the state was updated correctly.
        (, , uint256 expiry) = _term.parseAssetIdExternal(assetId);
        (uint128 pricePerShare, uint128 interest) = _term.finalizedTerms(
            expiry
        );
        // TODO: These could be helper functions in Test.sol
        if (pricePerShare != testCase.finalState.pricePerShare) {
            _logTestCaseReleaseYT("success case", testCase);
            assertEq(
                pricePerShare,
                testCase.finalState.pricePerShare,
                "unexpected pricePerShare"
            );
        }
        if (interest != testCase.finalState.interest - expectedValue) {
            _logTestCaseReleaseYT("success case", testCase);
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
            _logTestCaseReleaseYT("success case", testCase);
            assertEq(
                _term.sharesPerExpiry(expiry),
                testCase.sharesPerExpiry - expectedShares,
                "unexpected sharesPerExpiry"
            );
        }
        if (
            _term.totalSupply(assetId) != testCase.totalSupply - testCase.amount
        ) {
            _logTestCaseReleaseYT("success case", testCase);
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
            _logTestCaseReleaseYT("success case", testCase);
            assertEq(
                _term.balanceOf(assetId, source),
                testCase.sourceBalance - testCase.amount,
                "unexpected sourceBalance"
            );
        }
        (uint128 shares_, uint128 pt) = _term.yieldTerms(assetId);
        if (
            shares_ !=
            testCase.yieldState.shares -
                (testCase.yieldState.shares * testCase.amount) /
                testCase.totalSupply
        ) {
            _logTestCaseReleaseYT("success case", testCase);
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
            _logTestCaseReleaseYT("success case", testCase);
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
            _logTestCaseReleaseYT("success case", testCase);
            assertFalse(
                value >
                    (testCase.currentPricePerShare * testCase.sharesPerExpiry) /
                        _term.one(),
                "unexpectedly high value"
            );
        }
    }

    function _logTestCaseReleaseYT(
        string memory prelude,
        ReleaseYTTestCase memory testCase
    ) internal view {
        console2.log(prelude);
        console2.log("");
        console2.log("    amount                   = ", testCase.amount);
        console2.log(
            "    currentPricePerShare     = ",
            testCase.currentPricePerShare
        );
        console2.log(
            "    finalState.pricePerShare = ",
            testCase.finalState.pricePerShare
        );
        console2.log(
            "    finalState.interest      = ",
            testCase.finalState.interest
        );
        console2.log(
            "    sharesPerExpiry          = ",
            testCase.sharesPerExpiry
        );
        console2.log("    totalSupply              = ", testCase.totalSupply);
        console2.log(
            "    sourceBalance              = ",
            testCase.sourceBalance
        );
        console2.log(
            "    yieldState.shares        = ",
            testCase.yieldState.shares
        );
        console2.log("    yieldState.pt            = ", testCase.yieldState.pt);
        console2.log("");
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
        ReleasePTTestCase[] memory testCases = _convertToReleasePTTestCase(
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
            _term.setCurrentPricePerShare(
                testCases[i].currentPricePerShare,
                IYieldAdapter.ShareState.Locked
            );
            _term.setUserBalance(assetId, source, testCases[i].sourceBalance);
            _term.setTotalSupply(assetId, testCases[i].totalSupply);

            (
                bool shouldExpectError,
                bytes memory expectedError
            ) = _getExpectedErrorReleasePT(testCases[i]);
            if (shouldExpectError) {
                try
                    _term.releasePTExternal(
                        finalState,
                        assetId,
                        source,
                        testCases[i].amount
                    )
                {
                    _logTestCaseReleasePT("failure case", testCases[i]);
                    revert("succeeded unexpectedly");
                } catch (bytes memory error) {
                    if (Utils.neq(error, expectedError)) {
                        _logTestCaseReleasePT("failure case", testCases[i]);
                        assertEq(error, expectedError);
                    }
                }
            } else {
                try
                    _term.releasePTExternal(
                        finalState,
                        assetId,
                        source,
                        testCases[i].amount
                    )
                returns (uint256 shares, uint256 value) {
                    _validateSuccessReleasePT(
                        testCases[i],
                        assetId,
                        shares,
                        value
                    );
                } catch {
                    _logTestCaseReleasePT("success case", testCases[i]);
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
        // The source's balance of PT.
        uint256 sourceBalance;
    }

    // Converts a raw testing matrix to a structured array.
    function _convertToReleasePTTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (ReleasePTTestCase[] memory testCases)
    {
        testCases = new ReleasePTTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            _validateTestCaseLength(rawTestCases[i], 6);
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
    function _getExpectedErrorReleasePT(ReleasePTTestCase memory testCase)
        internal
        view
        returns (bool, bytes memory)
    {
        if (testCase.currentPricePerShare == 0) {
            return (true, stdError.divisionError);
        } else if (
            (testCase.interest * _term.one()) / testCase.currentPricePerShare >
            testCase.sharesPerExpiry
        ) {
            // TODO: Re-evaluate this case in the context of _releaseYT.
            return (true, stdError.arithmeticError);
        } else if (testCase.totalSupply == 0) {
            return (true, stdError.divisionError);
        } else if (
            testCase.amount > testCase.sourceBalance ||
            testCase.amount > testCase.totalSupply
        ) {
            return (true, stdError.arithmeticError);
        }
        return (false, new bytes(0));
    }

    // Given a test case, validate the state transitions and return values of a
    // successful call to _releasePT.
    function _validateSuccessReleasePT(
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
            _logTestCaseReleasePT("success case", testCase);
            assertEq(shares, expectedShares);
        }
        if (value != expectedValue) {
            _logTestCaseReleasePT("success case", testCase);
            assertEq(value, expectedValue);
        }

        // Ensure that the state was updated correctly.
        if (
            _term.totalSupply(assetId) != testCase.totalSupply - testCase.amount
        ) {
            _logTestCaseReleasePT("success case", testCase);
            assertEq(
                _term.totalSupply(assetId),
                testCase.totalSupply - testCase.amount
            );
        }
        if (
            _term.balanceOf(assetId, source) !=
            testCase.sourceBalance - testCase.amount
        ) {
            _logTestCaseReleasePT("success case", testCase);
            assertEq(
                _term.balanceOf(assetId, source),
                testCase.sourceBalance - testCase.amount
            );
        }
        if (
            _term.sharesPerExpiry(assetId) !=
            testCase.sharesPerExpiry - expectedShares
        ) {
            _logTestCaseReleasePT("success case", testCase);
            assertEq(
                _term.sharesPerExpiry(assetId),
                testCase.sharesPerExpiry - expectedShares
            );
        }
    }

    function _logTestCaseReleasePT(
        string memory prelude,
        ReleasePTTestCase memory testCase
    ) internal view {
        console2.log(prelude);
        console2.log("");
        console2.log("    amount               = ", testCase.amount);
        console2.log("    interest             = ", testCase.interest);
        console2.log("    sharesPerExpiry      = ", testCase.sharesPerExpiry);
        console2.log("    totalSupply          = ", testCase.totalSupply);
        console2.log(
            "    currentPricePerShare = ",
            testCase.currentPricePerShare
        );
        console2.log("    sourceBalance        = ", testCase.sourceBalance);
        console2.log("");
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

    // ------------------------- helpers ------------------------- //

    function _getFixturesAssetIdsAndAmounts(
        uint256 assetIdSelector,
        uint256 amountSelector
    )
        internal
        view
        returns (uint256[] memory assetIds, uint256[] memory amounts)
    {
        // Create the asset IDs fixture.
        require(
            assetIdSelector < 7,
            "Asset ID fixture selector must be less than 7"
        );
        if (assetIdSelector == 0) {
            assetIds = new uint256[](0);
        } else if (assetIdSelector == 1) {
            assetIds = new uint256[](1);
            assetIds[0] = Utils.encodeAssetId(false, 0, block.timestamp);
        } else if (assetIdSelector == 2) {
            // duplicated asset ID
            assetIds = new uint256[](2);
            assetIds[0] = Utils.encodeAssetId(false, 0, block.timestamp);
            assetIds[1] = Utils.encodeAssetId(false, 0, block.timestamp);
        } else if (assetIdSelector == 3) {
            // out of order asset IDs
            assetIds = new uint256[](2);
            assetIds[0] = Utils.encodeAssetId(
                true,
                block.timestamp / 2,
                block.timestamp
            );
            assetIds[1] = Utils.encodeAssetId(false, 0, block.timestamp);
        } else if (assetIdSelector == 4) {
            // out of order asset IDs and duplicate
            assetIds = new uint256[](2);
            assetIds[1] = Utils.encodeAssetId(false, 0, block.timestamp);
            assetIds[0] = Utils.encodeAssetId(
                true,
                block.timestamp / 2,
                block.timestamp
            );
            assetIds[1] = Utils.encodeAssetId(false, 0, block.timestamp);
        } else if (assetIdSelector == 5) {
            assetIds = new uint256[](1);
            assetIds[0] = Utils.encodeAssetId(true, 0, 0);
        } else if (assetIdSelector == 6) {
            assetIds = new uint256[](4);
            assetIds[0] = Utils.encodeAssetId(false, 0, block.timestamp);
            assetIds[1] = Utils.encodeAssetId(
                true,
                block.timestamp / 3,
                block.timestamp
            );
            assetIds[2] = Utils.encodeAssetId(
                true,
                block.timestamp / 2,
                block.timestamp
            );
            assetIds[3] = Utils.encodeAssetId(true, 0, 0);
        }

        // Create the amounts fixture.
        require(
            amountSelector < 6,
            "Amount fixture selector must be less than 6"
        );
        if (amountSelector == 0) {
            amounts = new uint256[](assetIds.length);
            for (uint256 i = 0; i < assetIds.length; i++) {
                amounts[i] = 0;
            }
        } else if (amountSelector == 1) {
            amounts = new uint256[](assetIds.length);
            for (uint256 i = 0; i < assetIds.length; i++) {
                amounts[i] = 1 ether;
            }
        } else if (amountSelector == 2) {
            amounts = new uint256[](assetIds.length);
            for (uint256 i = 0; i < assetIds.length; i++) {
                amounts[i] = 1 ether + i * 0.3453 ether + 123;
            }
        } else if (amountSelector == 3) {
            amounts = new uint256[](assetIds.length);
            for (uint256 i = 0; i < assetIds.length; i++) {
                amounts[i] = 203 ether - i * 2 ether + 123;
            }
        } else if (amountSelector == 4) {
            if (assetIds.length > 0) {
                amounts = new uint256[](assetIds.length - 1);
                for (uint256 i = 0; i < assetIds.length - 1; i++) {
                    amounts[i] = 203 ether - i * 2 ether + 123;
                }
            }
        } else if (amountSelector == 5) {
            amounts = new uint256[](assetIds.length + 1);
            for (uint256 i = 0; i < assetIds.length + 1; i++) {
                amounts[i] = 203 ether - i * 2 ether + 123;
            }
        }
    }
}
