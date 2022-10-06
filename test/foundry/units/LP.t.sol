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

    ForwarderFactory public factory;
    MockTerm public term;
    MockERC20Permit public token;
    MockLP public lp;

    // ------ events ------ //
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

    event Unlock(address destination, uint256 tokenId, uint256 amount);

    event DepositUnlocked(
        uint256 underlyingAmount,
        uint256 ptAmount,
        uint256 ptExpiry,
        address destination
    );

    event DepositFromShares(
        uint256 poolId,
        uint256 currentShares,
        uint256 currentBonds,
        uint256 depositedShares,
        uint256 pricePerShare,
        address to
    );

    event WithdrawToShares(uint256 poolId, uint256 amount, address source);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

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
        vm.warp(100);
        inputs[0] = new uint256[](2);
        inputs[0][0] = 1; // expired
        inputs[0][1] = 12345678; // active

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

    // -------------------  depositBonds unit tests   ------------------ //

    // quick sanity test.  deposit all the users bonds and shares into the pool
    function test_depositBonds() public {
        uint256 poolId = 12345678; // active
        uint256 bondsDeposited = 1 ether;
        address destination = address(user);
        uint256 minOutput = 1 ether;
        uint256 bondReserves = 1 ether;
        uint256 shareReserves = 1 ether;
        uint256 sharesNeeded = 1 ether;
        uint256 totalSupply = 1 ether;
        uint256 expectedLpTokens = 1 ether;

        // Set the address.
        startHoax(user);

        // setup
        term.setApprovalForAll(address(lp), true);
        term.setUserBalance(poolId, address(user), bondsDeposited); // give user bonds
        term.setUserBalance(_UNLOCKED_TERM_ID, address(user), sharesNeeded); // give user shares
        lp.setTotalSupply(poolId, totalSupply);
        lp.setBondReserves(poolId, uint128(bondReserves));
        lp.setShareReserves(poolId, uint128(shareReserves));

        expectStrictEmit();
        emit TransferSingle(
            address(lp), // caller
            address(user), // from
            address(lp), // to
            poolId, // tokenId
            bondsDeposited // amount
        );

        expectStrictEmit();
        emit TransferSingle(
            address(lp), // caller
            address(user), // from
            address(lp), // to
            _UNLOCKED_TERM_ID, // tokenId
            sharesNeeded // amount
        );

        expectStrictEmit();
        emit TransferSingle(
            address(user), // caller
            address(0), // from
            address(user), // to
            poolId, // tokenId
            expectedLpTokens // amount
        );

        uint256 newLpTokens = lp.depositBonds(
            poolId,
            bondsDeposited,
            destination,
            minOutput
        );

        assertEq(newLpTokens, expectedLpTokens);

        (uint256 reserveShares, uint256 reserveBonds) = lp.reserves(poolId);

        assertEq(reserveShares, shareReserves + sharesNeeded);
        assertEq(reserveBonds, bondReserves + bondsDeposited);
    }

    function test_depositFromBondsCombinatorial() public {
        uint256[][] memory inputs = new uint256[][](6);
        // poolId
        vm.warp(100);
        inputs[0] = new uint256[](2);
        inputs[0][0] = 1; // expired
        inputs[0][1] = 12345678; // active

        // bondsDeposited
        inputs[1] = new uint256[](4);
        inputs[1][0] = 0;
        inputs[1][1] = 100 + 311970;
        inputs[1][2] = 1 ether + 468966;
        inputs[1][3] = 10_000 ether + 849244;

        // shareReserves
        inputs[2] = new uint256[](3);
        inputs[2][0] = 0 ether;
        inputs[2][1] = 1 ether + 305566;
        inputs[2][2] = 10_000 ether + 842120;

        // bondReserves
        inputs[3] = new uint256[](3);
        inputs[3][0] = 0 ether;
        inputs[3][1] = 1 ether + 34447;
        inputs[3][2] = 10_000 ether + 180554;

        // totalSupply
        inputs[4] = new uint256[](3);
        inputs[4][0] = 0;
        inputs[4][1] = 1 ether + 329022;
        inputs[4][2] = 10_000 ether + 736043;

        // minOutput
        inputs[5] = new uint256[](3);
        inputs[5][0] = 0;
        inputs[5][1] = 1 ether + 207332;
        inputs[5][2] = 10_000 ether + 544908;

        DepositBondsTestCase[]
            memory testCases = _convertToDepositBondsTestCase(
                Utils.generateTestingMatrix(inputs)
            );

        // Set the address.
        startHoax(user);

        for (uint256 i = 0; i < testCases.length; i++) {
            DepositBondsTestCase memory testCase = testCases[i];

            _depositBondsSetup(testCase);

            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedDepositBondsError(testCase);

            // if there is an expected error, try to catch it
            if (testCaseIsError) {
                _validateDepositBondsTestCaseError(testCase, expectedError);
                // otherwise validate the test passes
            } else {
                _validateDepositBondsTestCase(testCase);
            }
        }
    }

    struct DepositBondsTestCase {
        // pool to deposit bonds to
        uint256 poolId;
        // the number of bonds to deposit
        uint256 bondsDeposited;
        // number of shares already in the pool
        uint256 shareReserves;
        // number of bonds already in the pool
        uint256 bondReserves;
        // total supply of lp in the pool
        uint256 totalSupply;
        // slippage tolerance for number of lp tokens to create
        uint256 minLpOut;
    }

    function _convertToDepositBondsTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (DepositBondsTestCase[] memory testCases)
    {
        testCases = new DepositBondsTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            _validateTestCaseLength(rawTestCases[i], 6);
            testCases[i] = DepositBondsTestCase({
                poolId: rawTestCases[i][0],
                bondsDeposited: rawTestCases[i][1],
                shareReserves: rawTestCases[i][2],
                bondReserves: rawTestCases[i][3],
                totalSupply: rawTestCases[i][4],
                minLpOut: rawTestCases[i][5]
            });
        }
    }

    function _depositBondsSetup(DepositBondsTestCase memory testCase) internal {
        // approvals beyond scope of these tests, approve for all
        term.setApprovalForAll(address(lp), true);
        // don't need to test if transfer fails from inadequate funds
        term.setUserBalance(testCase.poolId, address(user), 20_000 ether);
        // don't need to test if transfer fails from inadequate funds
        term.setUserBalance(
            _UNLOCKED_TERM_ID,
            address(user),
            type(uint256).max
        );

        lp.setTotalSupply(testCase.poolId, testCase.totalSupply);
        lp.setBondReserves(testCase.poolId, uint128(testCase.bondReserves));
        lp.setShareReserves(testCase.poolId, uint128(testCase.shareReserves));
    }

    function _getExpectedDepositBondsError(DepositBondsTestCase memory testCase)
        internal
        view
        returns (bool testCaseIsError, bytes memory reason)
    {
        // No minting after expiration
        if (testCase.poolId <= block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermExpired.selector)
            );
        }

        if (testCase.bondReserves == 0) {
            return (true, stdError.divisionError);
        }

        uint256 lpCreated = (testCase.totalSupply * testCase.bondsDeposited) /
            testCase.bondReserves;
        // Check enough has been made and return that amount
        if (lpCreated < testCase.minLpOut) {
            return (
                true,
                abi.encodeWithSelector(
                    ElementError.ExceededSlippageLimit.selector
                )
            );
        }
    }

    function _validateDepositBondsTestCaseError(
        DepositBondsTestCase memory testCase,
        bytes memory expectedError
    ) internal {
        try
            lp.depositBonds(
                testCase.poolId,
                testCase.bondsDeposited,
                address(user),
                testCase.minLpOut
            )
        {
            _logDepositBondsTestCase(testCase);
            revert ExpectedFailingTestPasses(expectedError);
        } catch (bytes memory err) {
            if (Utils.neq(err, expectedError)) {
                _logDepositBondsTestCase(testCase);
                revert ExpectedDifferentFailureReason(err, expectedError);
            }
        }
    }

    function _validateDepositBondsTestCase(DepositBondsTestCase memory testCase)
        internal
    {
        _registerExpectedDepositBondsEvents(testCase);
        uint256 lpCreated = lp.depositBonds(
            testCase.poolId,
            testCase.bondsDeposited,
            address(user),
            testCase.minLpOut
        );

        bytes memory emptyError = new bytes(0);

        // test that we are getting the correct lp created
        uint256 expectedLpCreated = (testCase.totalSupply *
            testCase.bondsDeposited) / testCase.bondReserves;
        if (lpCreated != expectedLpCreated) {
            assertEq(
                lpCreated,
                expectedLpCreated,
                "unexpected lp tokens created"
            );
            _logDepositBondsTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }

        // test that we are setting reserves correctly
        (uint256 poolReserveShares, uint256 poolReserveBonds) = lp.reserves(
            testCase.poolId
        );
        uint256 sharesNeeded = (testCase.shareReserves *
            testCase.bondsDeposited) / testCase.bondReserves;

        uint256 expectedReserveShares = testCase.shareReserves + sharesNeeded;
        uint256 expectedReserveBonds = testCase.bondReserves +
            testCase.bondsDeposited;

        if (poolReserveShares != expectedReserveShares) {
            assertEq(
                poolReserveShares,
                expectedReserveShares,
                "unexpected reserve shares value"
            );
            _logDepositBondsTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }

        if (poolReserveBonds != expectedReserveBonds) {
            assertEq(
                poolReserveBonds,
                expectedReserveBonds,
                "unexpected reserve bonds value"
            );
            _logDepositBondsTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }

        // test that we are updating totalSupply correctly
        uint256 totalSupply = lp.totalSupply(testCase.poolId);
        uint256 expectedTotalSupply = testCase.totalSupply + expectedLpCreated;

        if (totalSupply != expectedTotalSupply) {
            assertEq(
                totalSupply,
                expectedTotalSupply,
                "unexpected total supply value"
            );
            _logDepositBondsTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }
    }

    function _registerExpectedDepositBondsEvents(
        DepositBondsTestCase memory testCase
    ) internal {
        if (testCase.poolId > block.timestamp) {
            // user bonds to pool
            expectStrictEmit();
            emit TransferSingle(
                address(lp),
                address(user),
                address(lp),
                testCase.poolId,
                testCase.bondsDeposited
            );

            if (testCase.bondReserves > 0) {
                uint256 sharesNeeded = (testCase.shareReserves *
                    testCase.bondsDeposited) / testCase.bondReserves;
                // user shares to pool
                expectStrictEmit();
                emit TransferSingle(
                    address(lp),
                    address(user),
                    address(lp),
                    _UNLOCKED_TERM_ID,
                    sharesNeeded
                );

                uint256 lpCreated = (testCase.totalSupply *
                    testCase.bondsDeposited) / testCase.bondReserves;
                // mint lp for user
                expectStrictEmit();
                emit TransferSingle(
                    address(user),
                    address(0),
                    address(user),
                    testCase.poolId,
                    lpCreated
                );
            }
        }
    }

    function _logDepositBondsTestCase(DepositBondsTestCase memory testCase)
        internal
        view
    {
        console2.log("    LP.rollover Test #%s :: %s");
        console2.log("    -----------------------------------------------    ");
        console2.log("    poolId = ", testCase.poolId);
        console2.log("    bondsDeposited = ", testCase.bondsDeposited);
        console2.log("    bondReserves = ", testCase.bondReserves);
        console2.log("    shareReserves = ", testCase.shareReserves);
        console2.log("    shareReserves = ", testCase.totalSupply);
        console2.log("    shareReserves = ", testCase.minLpOut);
        console2.log("");
    }

    // -------------------  _depositFromShares unit tests   ------------------ //

    // quick sanity test.  if pricePerShare is 1, then bonds and shares are equal, so we should see 2 shares get converted into 2 bonds
    function test__depositFromShares() public {
        uint256 poolId = 12345678;
        uint256 currentShares = 10 ether;
        uint256 currentBonds = 10 ether;
        uint256 depositedShares = 4 ether;
        uint256 pricePerShare = 1 ether;

        lp.setTotalSupply(poolId, 10 ether);

        uint256 newLp = lp.depositFromSharesExternal(
            poolId,
            currentShares,
            currentBonds,
            depositedShares,
            pricePerShare,
            address(user)
        );

        assertEq(newLp, 2 ether);
    }

    function test__depositFromSharesCombinatorial() public {
        uint256[][] memory inputs = new uint256[][](6);
        // currentShares
        inputs[0] = new uint256[](3);
        inputs[0][0] = 0; // should throw error
        inputs[0][1] = 1 ether;
        inputs[0][2] = 2 ether;

        // currentBonds
        inputs[1] = new uint256[](3);
        inputs[1][0] = 0; // should throw error
        inputs[1][1] = 1 ether;
        inputs[1][2] = 2 ether;

        // depositedShares
        inputs[2] = new uint256[](4);
        inputs[2][0] = 0;
        inputs[2][1] = 1;
        inputs[2][2] = 1 ether;
        inputs[2][3] = 2 ether;

        // totalSupply
        inputs[3] = new uint256[](3);
        inputs[3][0] = 0;
        inputs[3][1] = 1 ether;
        inputs[3][2] = 2 ether;

        //pricePerShare
        inputs[4] = new uint256[](4);
        inputs[4][0] = 0;
        inputs[4][1] = 1 ether;
        inputs[4][2] = 1.5 ether;
        inputs[4][3] = 3 ether; // higher than 100% interest

        // poolId
        vm.warp(100);
        inputs[5] = new uint256[](2);
        inputs[5][0] = 1; // should throw error
        inputs[5][1] = 12345678;

        DepositSharesTestCase[]
            memory testCases = _convertToDepositSharesTestCase(
                Utils.generateTestingMatrix(inputs)
            );

        // Set the address.
        startHoax(user);

        for (uint256 i = 0; i < testCases.length; i++) {
            DepositSharesTestCase memory testCase = testCases[i];
            uint256 totalSupply = testCases[i].totalSupply;
            uint256 currentShares = testCases[i].currentShares;
            uint256 currentBonds = testCases[i].currentBonds;
            uint256 depositedShares = testCases[i].depositedShares;
            uint256 pricePerShare = testCases[i].pricePerShare;
            uint256 poolId = testCases[i].poolId;

            lp.setShareReserves(poolId, uint128(currentShares));
            lp.setBondReserves(poolId, uint128(currentBonds));
            lp.setTotalSupply(poolId, totalSupply);

            // See if we are expecting an error from the inputs
            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedDepositSharesError(testCase);

            // if there is an expected error, try to catch it
            if (testCaseIsError) {
                try
                    lp.depositFromSharesExternal(
                        poolId,
                        currentShares,
                        currentBonds,
                        depositedShares,
                        pricePerShare,
                        address(user)
                    )
                {
                    _logDepositSharesTestCase(testCase);
                    revert ExpectedFailingTestPasses(expectedError);
                } catch Error(string memory err) {
                    if (Utils.neq(bytes(err), expectedError)) {
                        _logDepositSharesTestCase(testCase);
                        revert ExpectedDifferentFailureReasonString(
                            err,
                            string(expectedError)
                        );
                    }
                } catch (bytes memory err) {
                    if (Utils.neq(err, expectedError)) {
                        _logDepositSharesTestCase(testCase);
                        revert ExpectedDifferentFailureReason(
                            err,
                            expectedError
                        );
                    }
                }
                // otherwise call the method and check the result
            } else {
                _validateDepositSharesTestCase(testCase);
            }
        }
    }

    struct DepositSharesTestCase {
        // the number of shares in the pool
        uint256 currentShares;
        // the number of bonds in the pool
        uint256 currentBonds;
        // the number of shares to deposit into the pool
        uint256 depositedShares;
        // total number of lp tokens in the pool
        uint256 totalSupply;
        // the number of underlying per share in 18 point decimal
        uint256 pricePerShare;
        // the expiration block timestamp of the term is the pool id
        uint256 poolId;
    }

    function _convertToDepositSharesTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (DepositSharesTestCase[] memory testCases)
    {
        testCases = new DepositSharesTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 6,
                "Raw test case must have length of 6."
            );
            testCases[i] = DepositSharesTestCase({
                currentShares: rawTestCases[i][0],
                currentBonds: rawTestCases[i][1],
                depositedShares: rawTestCases[i][2],
                totalSupply: rawTestCases[i][3],
                pricePerShare: rawTestCases[i][4],
                poolId: rawTestCases[i][5]
            });
        }
    }

    function _getExpectedDepositSharesError(
        DepositSharesTestCase memory testCase
    ) internal view returns (bool testCaseIsError, bytes memory reason) {
        if (testCase.currentBonds == 0 || testCase.currentShares == 0) {
            return (
                true,
                abi.encodeWithSelector(ElementError.PoolNotInitialized.selector)
            );
        }
        // where the input poolId is less than mined block timestamp
        if (testCase.poolId <= block.timestamp) {
            return (
                true,
                abi.encodeWithSelector(ElementError.TermExpired.selector)
            );
        }

        if (testCase.pricePerShare == 0) {
            return (true, stdError.divisionError);
        }
    }

    function _validateDepositSharesTestCase(
        DepositSharesTestCase memory testCase
    ) internal {
        uint256 totalSupply = testCase.totalSupply;
        uint256 currentShares = testCase.currentShares;
        uint256 currentBonds = testCase.currentBonds;
        uint256 depositedShares = testCase.depositedShares;
        uint256 pricePerShare = testCase.pricePerShare;
        uint256 poolId = testCase.poolId;
        // --- get the increase in shares --- //
        uint256 totalValue = (currentShares * pricePerShare) /
            1 ether +
            currentBonds;
        uint256 depositedAmount = (depositedShares * pricePerShare) / 1 ether;
        uint256 neededBonds = (depositedAmount * currentBonds) / totalValue;
        uint256 sharesToLock = (neededBonds * 1 ether) / pricePerShare;
        uint256 increaseInShares = depositedShares - sharesToLock;
        // ------ //
        uint256 newLpToken = (totalSupply * increaseInShares) / currentShares;

        _registerExpectedDepositSharesEvents(
            testCase,
            sharesToLock,
            newLpToken
        );
        uint256 result = lp.depositFromSharesExternal(
            poolId,
            currentShares,
            currentBonds,
            depositedShares,
            pricePerShare,
            address(user)
        );
        (uint128 shares, uint128 bonds) = lp.reserves(poolId);
        // make sure reserve state for shares checks out
        if (shares != currentShares + increaseInShares) {
            assertEq(
                shares,
                currentShares + increaseInShares,
                "shares not equal"
            );
            _logDepositSharesTestCase(testCase);
            revert ExpectedSharesNotEqual(
                shares,
                currentShares + increaseInShares
            );
        }

        // make sure reserve state for bonds checks out
        if (bonds != currentBonds + neededBonds) {
            assertEq(bonds, currentBonds + neededBonds, "bonds not equal");
            _logDepositSharesTestCase(testCase);
            revert ExpectedBondsNotEqual(bonds, currentBonds + neededBonds);
        }

        // make sure correct number of lp tokens are created
        if (result != newLpToken) {
            assertEq(result, newLpToken, "lp token result unexpected");
            _logDepositSharesTestCase(testCase);
            revert ExpectedLpTokensNotEqual(result, newLpToken);
        }
    }

    function _logDepositSharesTestCase(DepositSharesTestCase memory testCase)
        internal
        view
    {
        console2.log("    LP.depositFromShares");
        console2.log("    -----------------------------------------------    ");
        console2.log("    poolId           = ", testCase.poolId);
        console2.log("    depositedShares  = ", testCase.depositedShares);
        console2.log("    currentShares    = ", testCase.currentShares);
        console2.log("    currentBonds     = ", testCase.currentBonds);
        console2.log("    totalSupply      = ", testCase.totalSupply);
        console2.log("    pricePerShare    = ", testCase.pricePerShare);
        console2.log("");
    }

    function _registerExpectedDepositSharesEvents(
        DepositSharesTestCase memory testCase,
        uint256 sharesToLock,
        uint256 newLpToken
    ) internal {
        uint256[] memory assetIds = new uint256[](1);
        uint256[] memory assetAmounts = new uint256[](1);
        assetIds[0] = _UNLOCKED_TERM_ID;
        assetAmounts[0] = sharesToLock;

        expectStrictEmit();
        emit Lock(
            assetIds,
            assetAmounts,
            0,
            false,
            address(user),
            address(lp),
            block.timestamp,
            testCase.poolId
        );

        expectStrictEmit();
        emit TransferSingle(
            address(user),
            address(0),
            address(user),
            testCase.poolId,
            newLpToken
        );
    }

    // -------------------  _withdrawFromShares unit tests   ------------------ //

    // quick sanity test.  if the user has all the lp shares, they should pull out all the reserves.
    function test__withdrawToShares() public {
        uint256 poolId = 12345678;
        uint256 amount = 1 ether;
        address owner = address(user);

        // test the case of an active pool, should pull out all the shares and bonds
        lp.setLpBalance(poolId, owner, amount);
        lp.setTotalSupply(1 ether, poolId);
        lp.setBondReserves(poolId, 1 ether);
        lp.setShareReserves(poolId, 1 ether);
        term.setDepositUnlockedReturnValues(1 ether, 1 ether);

        (uint256 shares, uint256 bonds) = lp.withdrawToSharesExternal(
            poolId,
            amount,
            owner
        );

        assertEq(shares, 1 ether);
        assertEq(bonds, 1 ether);

        // test the case of an expired pool, should convert the bonds and pull out all shares
        vm.warp(poolId + 1); // expire the pool
        lp.setLpBalance(poolId, owner, amount);
        lp.setTotalSupply(1 ether, poolId);
        lp.setBondReserves(poolId, 1 ether);
        lp.setShareReserves(poolId, 1 ether);
        term.setDepositUnlockedReturnValues(1 ether, 1 ether);

        (shares, bonds) = lp.withdrawToSharesExternal(poolId, amount, owner);

        assertEq(shares, 2 ether);
        assertEq(bonds, 0 ether);
    }

    function test__withdrawToSharesCombinatorial() public {
        vm.warp(100);
        uint256[][] memory inputs = new uint256[][](7);
        // poolId
        inputs[0] = new uint256[](2);
        inputs[0][0] = 1; //expired
        inputs[0][1] = 12345678; // active

        // amount
        inputs[1] = new uint256[](3);
        inputs[1][0] = 0;
        inputs[1][1] = 1 ether + 134703;
        inputs[1][2] = 2 ether + 719740;

        // lpBalance
        inputs[2] = new uint256[](2);
        inputs[2][0] = 1 ether + 460133;
        inputs[2][1] = 2 ether + 490900;

        // totalSupply
        inputs[3] = new uint256[](3);
        inputs[3][0] = 0;
        inputs[3][1] = 2 ether + 565674;
        inputs[3][2] = 10_000 ether + 660156;

        // bondReserves
        inputs[4] = new uint256[](3);
        inputs[4][0] = 0;
        inputs[4][1] = 1 ether + 328070;
        inputs[4][2] = 10_000 ether + 827039;

        // shareReserves
        inputs[5] = new uint256[](3);
        inputs[5][0] = 0;
        inputs[5][1] = 1 ether + 976842;
        inputs[5][2] = 10_000 ether + 689760;

        // pricePerShare
        inputs[6] = new uint256[](3);
        inputs[6][0] = 0.5 ether;
        inputs[6][1] = 1 ether;
        inputs[6][2] = 2 ether;

        WithdrawToSharesTestCase[]
            memory testCases = _convertToWithdrawToSharesTestCase(
                Utils.generateTestingMatrix(inputs)
            );

        // Set the address.
        startHoax(user);

        for (uint256 i = 0; i < testCases.length; i++) {
            WithdrawToSharesTestCase memory testCase = testCases[i];
            _withdrawToSharesTestCaseSetup(testCase);
            // See if we are expecting an error from the inputs
            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedWithdrawToSharesError(testCase);

            // if there is an expected error, try to catch it
            if (testCaseIsError) {
                _validateWithdrawToSharesTestCaseError(testCase, expectedError);
                // otherwise validate the test passes
            } else {
                _validateWithdrawToSharesTestCase(testCase);
            }
        }
    }

    struct WithdrawToSharesTestCase {
        // the expiration block timestamp of the term is the pool id
        uint256 poolId;
        // amount to withdraw to shares
        uint256 amount;
        // the lp token balance of the user
        uint256 lpBalance;
        // the total supply of lp tokens in the pool
        uint256 totalSupply;
        // the bond reserves for the pool
        uint256 bondReserves;
        // the share reserves for the pool
        uint256 shareReserves;
        // the number of underlying per share
        uint256 pricePerShare;
    }

    function _convertToWithdrawToSharesTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (WithdrawToSharesTestCase[] memory testCases)
    {
        testCases = new WithdrawToSharesTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            _validateTestCaseLength(rawTestCases[i], 7);
            testCases[i] = WithdrawToSharesTestCase({
                poolId: rawTestCases[i][0],
                amount: rawTestCases[i][1],
                lpBalance: rawTestCases[i][2],
                totalSupply: rawTestCases[i][3],
                bondReserves: rawTestCases[i][4],
                shareReserves: rawTestCases[i][5],
                pricePerShare: rawTestCases[i][6]
            });
        }
    }

    function _withdrawToSharesTestCaseSetup(
        WithdrawToSharesTestCase memory testCase
    ) internal {
        uint256 poolId = testCase.poolId;
        uint256 lpBalance = testCase.lpBalance;
        uint256 totalSupply = testCase.totalSupply;
        uint128 bondReserves = uint128(testCase.bondReserves);
        uint128 shareReserves = uint128(testCase.shareReserves);

        lp.setLpBalance(poolId, address(user), lpBalance);
        lp.setTotalSupply(poolId, totalSupply);
        lp.setBondReserves(poolId, bondReserves);
        lp.setShareReserves(poolId, shareReserves);
        uint256 sharesCreated = bondReserves / testCase.pricePerShare;
        term.setDepositUnlockedReturnValues(bondReserves, sharesCreated);

        vm.warp(1);
    }

    function _getExpectedWithdrawToSharesError(
        WithdrawToSharesTestCase memory testCase
    ) internal view returns (bool testCaseIsError, bytes memory reason) {
        // tries to burn more than there is
        if (testCase.amount > testCase.totalSupply) {
            return (true, stdError.arithmeticError);
        }

        // calculating userShares and userBonds will divide by zero
        if (testCase.totalSupply == 0) {
            return (true, stdError.divisionError);
        }

        uint256 bondReserves = testCase.bondReserves;
        uint256 shareReserves = testCase.shareReserves;
        if (block.timestamp >= testCase.poolId && bondReserves != 0) {
            shareReserves += bondReserves / testCase.pricePerShare;
            bondReserves = 0;
        }

        uint256 userShares = (testCase.amount * shareReserves) /
            testCase.totalSupply;

        // can't subtract more shares than there are in reserves
        if (userShares > shareReserves) {
            return (true, stdError.arithmeticError);
        }

        uint256 userBonds = (testCase.amount * bondReserves) /
            testCase.totalSupply;

        // can't subtract more bonds than there are in reserves
        if (userBonds > bondReserves) {
            return (true, stdError.arithmeticError);
        }
    }

    function _validateWithdrawToSharesTestCaseError(
        WithdrawToSharesTestCase memory testCase,
        bytes memory expectedError
    ) internal {
        try
            lp.withdrawToSharesExternal(
                testCase.poolId,
                testCase.amount,
                address(user)
            )
        {
            _logWithdrawToSharesTestCase(testCase);
            revert ExpectedFailingTestPasses(expectedError);
        } catch (bytes memory err) {
            if (Utils.neq(err, expectedError)) {
                _logWithdrawToSharesTestCase(testCase);
                revert ExpectedDifferentFailureReason(err, expectedError);
            }
        } catch Error(string memory err) {
            if (Utils.neq(bytes(err), expectedError)) {
                _logWithdrawToSharesTestCase(testCase);
                revert ExpectedDifferentFailureReasonString(
                    err,
                    string(expectedError)
                );
            }
        }
    }

    function _validateWithdrawToSharesTestCase(
        WithdrawToSharesTestCase memory testCase
    ) internal {
        _registerExpectedWithdrawToSharesEvents(testCase);
        (uint256 userShares, uint256 userBonds) = lp.withdrawToSharesExternal(
            testCase.poolId,
            testCase.amount,
            address(user)
        );

        uint256 bondReserves = testCase.bondReserves;
        uint256 shareReserves = testCase.shareReserves;
        if (block.timestamp >= testCase.poolId && testCase.bondReserves != 0) {
            shareReserves += bondReserves / testCase.pricePerShare;
            bondReserves = 0;
        }

        uint256 expectedUserShares = (testCase.amount * shareReserves) /
            testCase.totalSupply;
        uint256 expectedUserBonds = (testCase.amount * bondReserves) /
            testCase.totalSupply;

        bytes memory emptyError = new bytes(0);

        if (userShares != expectedUserShares) {
            assertEq(userShares, expectedUserShares, "unexpected shares value");
            _logWithdrawToSharesTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }

        if (userBonds != expectedUserBonds) {
            assertEq(userBonds, expectedUserBonds, "unexpected bonds value");
            _logWithdrawToSharesTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }

        (uint256 poolReserveShares, uint256 poolReserveBonds) = lp.reserves(
            testCase.poolId
        );
        uint256 expectedReserveShares = shareReserves - userShares;
        uint256 expectedReserveBonds = bondReserves - userBonds;

        if (poolReserveShares != expectedReserveShares) {
            assertEq(
                poolReserveShares,
                expectedReserveShares,
                "unexpected reserve shares value"
            );
            _logWithdrawToSharesTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }

        if (poolReserveBonds != expectedReserveBonds) {
            assertEq(
                poolReserveBonds,
                expectedReserveBonds,
                "unexpected reserve bonds value"
            );
            _logWithdrawToSharesTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }
    }

    function _registerExpectedWithdrawToSharesEvents(
        WithdrawToSharesTestCase memory testCase
    ) internal {
        if (block.timestamp >= testCase.poolId && testCase.bondReserves != 0) {
            expectStrictEmit();
            emit DepositUnlocked(
                0,
                testCase.bondReserves,
                testCase.poolId,
                address(lp)
            );
        }

        expectStrictEmit();
        emit TransferSingle(
            address(user),
            address(user),
            address(0),
            testCase.poolId,
            testCase.amount
        );
    }

    function _logWithdrawToSharesTestCase(
        WithdrawToSharesTestCase memory testCase
    ) internal view {
        console2.log("    LP.withdrawToShares");
        console2.log("    -----------------------------------------------    ");
        console2.log("    poolId           = ", testCase.poolId);
        console2.log("    amount           = ", testCase.amount);
        console2.log("    lpBalance        = ", testCase.lpBalance);
        console2.log("    totalSupply      = ", testCase.totalSupply);
        console2.log("    bondReserves     = ", testCase.bondReserves);
        console2.log("    shareReserves    = ", testCase.shareReserves);
        console2.log("    pricePerShare    = ", testCase.pricePerShare);
        console2.log("");
    }

    // -------------------  rollover unit tests   ------------------ //

    // quick sanity test. should rollover all the users assets
    function test_rollover() public {
        vm.warp(100);
        uint256 fromPoolId = 1;
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
        inputs[0][0] = 1; // expired
        inputs[0][1] = 12345678; // active

        // toPoolId
        inputs[1] = new uint256[](2);
        inputs[1][0] = 1; // expired
        inputs[1][1] = 12345678; // active

        // amount
        inputs[2] = new uint256[](3);
        inputs[2][0] = 0 ether;
        inputs[2][1] = 1 ether + 946274;
        inputs[2][2] = 10_000 ether + 767463;

        // minOutput
        inputs[3] = new uint256[](3);
        inputs[3][0] = 0;
        inputs[3][1] = 1 ether + 864356;
        inputs[3][2] = 10_000 ether + 918720;

        // newLpToken
        inputs[4] = new uint256[](3);
        inputs[4][0] = 0;
        inputs[4][1] = 1 ether + 381279;
        inputs[4][2] = 10_000 ether + 503577;

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
            _validateTestCaseLength(rawTestCases[i], 4);
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

    // -------------------  withdraw unit tests   ------------------ //

    // should withdraw userShares and userBonds
    function test_withdraw() public {
        vm.warp(100);
        uint256 poolId = 1;
        uint256 amount = 1 ether;
        address destination = address(user);
        uint256 userShares = 1 ether;

        startHoax(address(user));

        // try case where bonds do and don't transfer to the user
        uint256[] memory testCases = new uint256[](2);
        testCases[0] = 0;
        testCases[1] = 1 ether;
        for (uint256 i; i < testCases.length; i++) {
            uint256 userBonds = testCases[i];
            lp.setWithdrawToSharesReturnValues(userShares, userBonds);
            lp.setDepositFromSharesReturnValue(1 ether);
            term.setUserBalance(poolId, address(lp), userBonds);

            expectStrictEmit();
            emit WithdrawToShares(
                poolId,
                1 ether, // amount
                destination // source
            );

            expectStrictEmit();
            emit Unlock(
                destination,
                _UNLOCKED_TERM_ID, // tokenId
                userShares // amount
            );

            if (userBonds != 0) {
                expectStrictEmit();
                emit TransferSingle(
                    address(lp), // caller
                    address(lp), // from
                    address(user), // to
                    poolId, // tokenId
                    userBonds // amount
                );
            }

            lp.withdraw(poolId, amount, destination);
        }
    }
}
