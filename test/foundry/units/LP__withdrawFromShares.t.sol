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
    error TestFail();
    error ExpectedSharesNotEqual(uint256 value, uint256 expected);
    error ExpectedBondsNotEqual(uint256 value, uint256 expected);
    error ExpectedLpTokensNotEqual(uint256 value, uint256 expected);

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
        uint256[][] memory inputs = new uint256[][](7);
        // poolId
        inputs[0] = new uint256[](2);
        inputs[0][0] = 0; //expired
        inputs[0][1] = 12345678; // active

        // amount
        inputs[1] = new uint256[](3);
        inputs[1][0] = 0;
        inputs[1][1] = 1 ether;
        inputs[1][2] = 2 ether;

        // lpBalance
        inputs[2] = new uint256[](2);
        inputs[2][0] = 1 ether;
        inputs[2][1] = 2 ether;

        // totalSupply
        inputs[3] = new uint256[](3);
        inputs[3][0] = 0;
        inputs[3][1] = 2 ether;
        inputs[3][2] = 10_000 ether;

        // bondReserves
        inputs[4] = new uint256[](3);
        inputs[4][0] = 0;
        inputs[4][1] = 1 ether;
        inputs[4][2] = 10_000 ether;

        // shareReserves
        inputs[5] = new uint256[](3);
        inputs[5][0] = 0;
        inputs[5][1] = 1 ether;
        inputs[5][2] = 10_000 ether;

        // pricePerShare
        inputs[6] = new uint256[](3);
        inputs[6][0] = 0.5 ether;
        inputs[6][1] = 1 ether;
        inputs[6][2] = 2 ether;

        WithdrawSharesTestCase[]
            memory testCases = _convertToWithdrawSharesTestCase(
                Utils.generateTestingMatrix(inputs)
            );

        // Set the address.
        startHoax(user);

        for (uint256 i = 0; i < testCases.length; i++) {
            WithdrawSharesTestCase memory testCase = testCases[i];
            _withdrawSharesTestCaseSetup(testCase);
            // See if we are expecting an error from the inputs
            (
                bool testCaseIsError,
                bytes memory expectedError
            ) = _getExpectedWithdrawSharesError(testCase);

            // if there is an expected error, try to catch it
            if (testCaseIsError) {
                _validateWithdrawSharesTestCaseError(testCase, expectedError);
                // otherwise validate the test passes
            } else {
                _validateWithdrawSharesTestCase(testCase);
            }
        }
    }

    struct WithdrawSharesTestCase {
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

    function _convertToWithdrawSharesTestCase(uint256[][] memory rawTestCases)
        internal
        pure
        returns (WithdrawSharesTestCase[] memory testCases)
    {
        testCases = new WithdrawSharesTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 7,
                "Raw test case must have length of 7."
            );
            testCases[i] = WithdrawSharesTestCase({
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

    function _withdrawSharesTestCaseSetup(
        WithdrawSharesTestCase memory testCase
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

    function _getExpectedWithdrawSharesError(
        WithdrawSharesTestCase memory testCase
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

    function _validateWithdrawSharesTestCaseError(
        WithdrawSharesTestCase memory testCase,
        bytes memory expectedError
    ) internal {
        try
            lp.withdrawToSharesExternal(
                testCase.poolId,
                testCase.amount,
                address(user)
            )
        {
            _logWithdrawSharesTestCase(testCase);
            revert ExpectedFailingTestPasses(expectedError);
        } catch (bytes memory err) {
            if (Utils.neq(err, expectedError)) {
                _logWithdrawSharesTestCase(testCase);
                revert ExpectedDifferentFailureReason(err, expectedError);
            }
        } catch Error(string memory err) {
            if (Utils.neq(bytes(err), expectedError)) {
                _logWithdrawSharesTestCase(testCase);
                revert ExpectedDifferentFailureReasonString(
                    err,
                    string(expectedError)
                );
            }
        }
    }

    function _validateWithdrawSharesTestCase(
        WithdrawSharesTestCase memory testCase
    ) internal {
        _registerExpectedWithdrawSharesEvents(testCase);
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

        bytes memory emptyError;

        if (userShares != expectedUserShares) {
            assertEq(userShares, expectedUserShares, "unexpected shares value");
            _logWithdrawSharesTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }

        if (userBonds != expectedUserBonds) {
            assertEq(userBonds, expectedUserBonds, "unexpected bonds value");
            _logWithdrawSharesTestCase(testCase);
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
            _logWithdrawSharesTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }

        if (poolReserveBonds != expectedReserveBonds) {
            assertEq(
                poolReserveBonds,
                expectedReserveBonds,
                "unexpected reserve bonds value"
            );
            _logWithdrawSharesTestCase(testCase);
            revert ExpectedPassingTestFails(emptyError);
        }
    }

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

    function _registerExpectedWithdrawSharesEvents(
        WithdrawSharesTestCase memory testCase
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

    function _logWithdrawSharesTestCase(WithdrawSharesTestCase memory testCase)
        internal
        view
    {
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
}
