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

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    event DepositBonds(uint256 poolId, uint256 amount, address source);
    event DepositFromShares(
        uint256 poolId,
        uint256 currentShares,
        uint256 currentBonds,
        uint256 depositedShares,
        uint256 pricePerShare,
        address to
    );

    uint256 internal constant _UNLOCKED_TERM_ID = 1 << 255;
    address public user = makeAddress("User");

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
        vm.warp(1);
        inputs[0] = new uint256[](2);
        inputs[0][0] = 0; // active
        inputs[0][1] = 12345678; // expired

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
}
