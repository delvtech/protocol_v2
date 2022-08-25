// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/Term.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "contracts/mocks/MockYieldAdapter.sol";
import "contracts/mocks/MockERC20YearnVault.sol";
import "contracts/interfaces/IERC20.sol";

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

// Unit tests for the lock function on a simple Term.  MockYieldAdapter is used as
// for the Term implementation.  Cases cover all asset types, pre-funding, sorting.
contract TermTestUnlock is Test {
    uint256 public constant UNLOCKED_YT_ID = 1 << 255;
    ForwarderFactory public ff;
    MockYieldAdapter public term;
    MockERC20Permit public token;
    MockERC20YearnVault public yearnVault;
    User public user;
    uint256[] public assetIds;
    uint256[] public assetAmounts;

    function setUp() public {
        ff = new ForwarderFactory();
        token = new MockERC20Permit("Test Token", "tt", 18);
        user = new User();
        yearnVault = new MockERC20YearnVault(address(token));
        yearnVault.authorize(address(user));
        bytes32 linkerCodeHash = bytes32(0);
        address governanceContract = address(
            0xEA674fdDe714fd979de3EdF0F56AA9716B898ec8
        );

        term = new MockYieldAdapter(
            address(yearnVault),
            governanceContract,
            linkerCodeHash,
            address(ff),
            token
        );

        // clear arrays before every test
        while (assetIds.length > 0) {
            assetIds.pop();
            assetAmounts.pop();
        }
    }

    // Testing the zero's case where all values are zero.
    function testUnlock_AllZeroValues() public {
        address destination = address(0);

        // give user some ETH and send requests as the user.
        startHoax(address(user));

        uint256 value = term.unlock(destination, assetIds, assetAmounts);

        assertEq(value, 0);
        assertEq(term.totalSupply(UNLOCKED_YT_ID), 0);
    }

    // test unlocking only unlocked assets
    function testUnlock_OnlyUnlockedAssets(
        uint128 underlyingAmount,
        uint128 profit
    ) public {
        vm.assume(
            underlyingAmount < 100_000_000 ether &&
                underlyingAmount > 1_000_000_000
        );
        vm.assume(profit < underlyingAmount);

        // give user some ETH and send requests as the user.
        startHoax(address(user));

        token.setBalance(address(user), underlyingAmount + profit);
        token.approve(address(term), UINT256_MAX);

        // create some unlocked assets
        term.depositUnlocked(underlyingAmount, 0, 0, address(user));
        uint256 userUnlockedBalance = term.balanceOf(
            UNLOCKED_YT_ID,
            address(user)
        );

        assetIds.push(UNLOCKED_YT_ID);
        assetAmounts.push(userUnlockedBalance);

        // add some profit to the yearn vault
        // this has to happen before we skip ahead in time since the mock vault pro-rates profit
        // from the last time it was added.
        token.approve(address(yearnVault), UINT256_MAX);
        yearnVault.report(profit);

        uint256 value = term.unlock(address(user), assetIds, assetAmounts);

        assertApproxEqAbs(
            value,
            underlyingAmount + profit,
            100,
            "value not equal amount deposited"
        );
    }

    // if the caller does not have enough unlocked assets, revert.
    function testFailUnlock_NotEnoughUnlockedAssets() public {
        // give user some ETH and send requests as the user.
        startHoax(address(user));

        uint256 amountDepositedUnlocked = 1 ether;
        token.setBalance(address(user), amountDepositedUnlocked);
        token.approve(address(term), UINT256_MAX);

        // create some unlocked assets
        term.depositUnlocked(amountDepositedUnlocked, 0, 0, address(user));
        uint256 userUnlockedBalance = term.balanceOf(
            UNLOCKED_YT_ID,
            address(user)
        );

        assetIds.push(UNLOCKED_YT_ID);
        // try to redeem 1 more than the user has
        assetAmounts.push(userUnlockedBalance + 1);

        // should fail
        uint256 value = term.unlock(address(user), assetIds, assetAmounts);
        assertEq(value, 0);
    }

    // test when only mature principal tokens should be unlocked
    function testUnlock_OnlyPrincipalTokens(
        uint128 underlyingAmount,
        uint128 profit,
        uint128 unlockAmount
    ) public {
        vm.assume(underlyingAmount < 100_000_000 ether && underlyingAmount > 0);
        vm.assume(profit < underlyingAmount);
        vm.assume(unlockAmount < underlyingAmount && unlockAmount > 0);

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        uint256 ytBeginDate = 1;
        uint256 expiration = 10;

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), underlyingAmount + profit);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some pts
        term.lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        // add some profit to the yearn vault
        // this has to happen before we skip ahead in time since the mock vault pro-rates profit
        // from the last time it was added.
        token.approve(address(yearnVault), UINT256_MAX);
        yearnVault.report(profit);

        // expire the tokens
        skip(expiration);

        // now unlock with only expired pts
        assetIds.push(expiration); // pt id's are just the expiration
        assetAmounts.push(unlockAmount);

        uint256 unlockedValue = term.unlock(
            address(user),
            assetIds,
            assetAmounts
        );

        uint256 userBalance = token.balanceOf(address(user));
        if (unlockedValue < 1 ether) {
            assertApproxEqAbs(
                unlockAmount,
                unlockedValue,
                100,
                "unlockAmount not equal to unlockedValue"
            );
            assertApproxEqAbs(
                userBalance,
                unlockAmount,
                100,
                "tokens not transferred to user"
            );
        } else {
            assertApproxEqRel(
                unlockAmount,
                unlockedValue,
                0.0000001 ether,
                "unlockAmount not equal to unlockedValue"
            );
            assertApproxEqRel(
                userBalance,
                unlockAmount,
                0.0000001 ether,
                "tokens not transferred to user"
            );
        }
    }

    // test when only principal tokens are not mature, should revert
    function testFailUnlock_OnlyPrincipalTokens(
        uint128 underlyingAmount,
        uint128 unlockAmount
    ) public {
        vm.assume(underlyingAmount < 100_000_000 ether && underlyingAmount > 0);
        vm.assume(unlockAmount < underlyingAmount && unlockAmount > 0);

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        uint256 ytBeginDate = 1;
        uint256 expiration = 10;

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), underlyingAmount);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some pts
        term.lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        // ALMOST expire the tokens
        skip(expiration - 2);

        // now try to unlock with non-expired pts
        assetIds.push(expiration); // pt id's are just the expiration
        assetAmounts.push(unlockAmount);
        // should fail
        term.unlock(address(user), assetIds, assetAmounts);
    }

    // test when only mature yield tokens should be locked
    function testUnlock_OnlyYieldTokens(
        uint128 underlyingAmount,
        uint128 profit
    ) public {
        vm.assume(underlyingAmount < 100_000_000 ether && underlyingAmount > 0);
        vm.assume(profit < underlyingAmount);
        vm.assume(profit > 0.1 ether);

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        // block.timestamp starts at 1.  don't use block.timestamp because it is buggy when used
        // with vm.warp() or skip()
        uint256 ytBeginDate = 1;
        uint256 expiration = 10_000_000_000;

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), underlyingAmount + profit);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some yts
        (, uint256 ytShares) = term.lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        // add some profit to the yearn vault
        token.approve(address(yearnVault), UINT256_MAX);
        yearnVault.report(profit);

        // expire the tokens
        skip(expiration);

        // now unlock with only yts
        uint256 yieldTokenId = (1 << 255) + (ytBeginDate << 128) + expiration;
        assetIds.push(yieldTokenId);
        assetAmounts.push(ytShares);
        uint256 unlockedValue = term.unlock(
            address(user),
            assetIds,
            assetAmounts
        );

        uint256 userBalance = token.balanceOf(address(user));
        assertApproxEqRel(
            profit,
            unlockedValue,
            0.000_000_1 ether,
            "profit not equal to unlockedValue"
        );
        assertApproxEqRel(
            userBalance,
            unlockedValue,
            0.000_000_1 ether,
            "tokens not transferred to user rel"
        );
    }

    // test unlocking when yield tokens are not expired, should revert
    function testFailUnlock_YieldTokensNotExpired() public {
        uint256 underlyingAmount = 1 ether;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        uint256 ytBeginDate = 1;
        uint256 expiration = 10_000_000;

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some yts
        term.lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        // add some profit to the yearn vault
        // this has to happen before we skip ahead in time since the mock vault pro-rates profit
        // from the last time it was added.
        token.approve(address(yearnVault), UINT256_MAX);
        uint256 profit = 0.5 ether;
        yearnVault.report(profit);

        // ALMOST expire the tokens
        skip(expiration - 2);

        // now try to unlock with only yts
        uint256 yieldTokenId = (1 << 255) + (ytBeginDate << 128) + expiration;
        assetIds.push(yieldTokenId); // pt id's are just the expiration
        assetAmounts.push(1 ether);

        term.unlock(address(user), assetIds, assetAmounts);
    }

    // tests many combinations of assets.  this is a sanity check and just makes sure that the
    // lock transactions don't fail.  also tests when there is both underlying and prefunded
    // underlying.
    function testUnlock_Combinations(
        uint64 numUnlockedAssets,
        uint64 numPts2,
        uint64 numPts1,
        uint64 numYts2,
        uint64 numYts1
    ) public {
        uint256 underlyingAmount = 20 ether;
        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        // block.timestamp starts at 1.  don't use block.timestamp because it is buggy when used
        // with vm.warp() or skip()
        uint256 timeStamp = 1;
        uint256 ytBeginDate = 1;
        uint256 expiration = 10_000_000;

        // give user some ETH and send requests as the user
        startHoax(address(user));
        token.setBalance(address(user), 1000 ether);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some pts and yts
        term.lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        skip(2_500_000);

        uint256 ytBeginDate2 = timeStamp + 2_500_000;
        uint256 expiration2 = 5_000_000;
        // do another lock to get different pts and yts
        term.lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate2,
            expiration2
        );

        // get some unlocked assets as well
        uint256 amountDepositedUnlocked = 20 ether;
        term.depositUnlocked(amountDepositedUnlocked, 0, 0, address(user));

        // expire the tokens
        skip(expiration);

        // add some profit to the yearn vault
        // this has to happen before we skip ahead in time since the mock vault pro-rates profit
        // from the last time it was added.
        token.approve(address(yearnVault), UINT256_MAX);
        // we lock underlyingAmount twice, set the profit to half that.
        uint256 profit = underlyingAmount;
        yearnVault.report(profit);

        uint256 yieldTokenId = (1 << 255) + (ytBeginDate << 128) + expiration;
        uint256 yieldTokenId2 = (1 << 255) +
            (ytBeginDate2 << 128) +
            expiration2;

        if (numPts2 > 1) {
            assetIds.push(expiration2);
            assetAmounts.push(uint256(numPts2));
        }

        if (numPts1 > 1) {
            assetIds.push(expiration);
            assetAmounts.push(uint256(numPts1));
        }

        if (numUnlockedAssets > 1) {
            assetIds.push(UNLOCKED_YT_ID);
            assetAmounts.push(uint256(numUnlockedAssets));
        }

        if (numYts1 > 1) {
            assetIds.push(yieldTokenId);
            assetAmounts.push(uint256(numYts1));
        }

        if (numYts2 > 1) {
            assetIds.push(yieldTokenId2);
            assetAmounts.push(uint256(numYts2));
        }

        // can't withdraw zero assets from vault, make sure there's at least 1
        if (assetIds.length > 0) {
            term.unlock(address(user), assetIds, assetAmounts);
        }
    }
}
