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
        inputs[5] = new uint256[](2);
        inputs[5][0] = 0; // should throw error
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
        DepositSharesTestCase memory testCase,
        uint256 testIndex
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

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

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
}
