// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";
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

contract TermTestLock is Test {
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

    // Testing the zero's case where all values are zero.  The exceptions here are ytBeginDate and expiration.
    function testLock_AllZeroValues() public {
        uint256 underlyingAmount = 0;

        address ytDestination = address(0);
        address ptDestination = address(0);
        bool hasPreFunding = false;
        uint256 ytBeginDate = block.timestamp;
        uint256 expiration = block.timestamp + 60 * 60 * 24 * 7; // one week in seconds

        // give user some ETH and send requests as the user.
        startHoax(address(user));

        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        (uint256 shares, uint256 value) = term.lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        assertEq(value, 0);
        assertEq(shares, 0);
        assertEq(term.totalSupply(UNLOCKED_YT_ID), 0);
    }

    // Deposit only underlying asset
    function testLock_OnlyUnderlying() public {
        uint256 underlyingAmount = 1 ether;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;
        uint256 ytBeginDate = block.timestamp;
        uint256 expiration = block.timestamp + 60 * 60 * 24 * 7; // one week in seconds

        // give user some ETH and send requests as the user.
        startHoax(address(user));

        token.setBalance(address(user), underlyingAmount);
        token.approve(address(term), UINT256_MAX);

        (uint256 shares, uint256 value) = term.lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        assertEq(value, underlyingAmount, "value not equal to underlying");
        assertEq(shares, value, "shares not equal to value");
        assertEq(
            term.totalSupply(expiration),
            underlyingAmount,
            "totalSupply incorrect"
        );
    }

    function testFailLock_NotEnoughUnderlying() public {
        uint256 underlyingAmount = 1 ether;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;
        uint256 ytBeginDate = block.timestamp;
        uint256 expiration = block.timestamp + 60 * 60 * 24 * 7; // one week in seconds

        // give user some ETH and send requests as the user.
        startHoax(address(user));

        // should fail because we give the user less than we are trying to deposit
        token.setBalance(address(user), underlyingAmount - 1);
        token.approve(address(term), UINT256_MAX);

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
    }

    function testLock_OnlyUnlockedAssets() public {
        uint256 underlyingAmount = 0;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;
        uint256 ytBeginDate = block.timestamp;
        uint256 expiration = block.timestamp + 60 * 60 * 24 * 7; // one week in seconds

        // give user some ETH and send requests as the user.
        startHoax(address(user));

        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        uint256 amountDepositedUnlocked = 1 ether;
        term.depositUnlocked(amountDepositedUnlocked, 0, 0, address(user));
        uint256 userUnlockedBalance = term.balanceOf(
            UNLOCKED_YT_ID,
            address(user)
        );

        assetIds.push(UNLOCKED_YT_ID);
        assetAmounts.push(userUnlockedBalance);

        (uint256 shares, uint256 value) = term.lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        assertEq(
            value,
            amountDepositedUnlocked,
            "value not equal amount deposited"
        );

        assertEq(shares, value, "shares not equal to value");
        assertEq(
            term.totalSupply(expiration),
            amountDepositedUnlocked,
            "totalSupply incorrect"
        );

        uint256 yieldTokenId = (1 << 255) + (ytBeginDate << 128) + expiration;
        uint256 userYts = term.balanceOf(yieldTokenId, address(user));
        uint256 userPts = term.balanceOf(expiration, address(user));
        assertEq(userYts, shares);
        assertEq(userPts, shares);
    }

    function testFailLock_NotEnoughUnlockedAssets() public {
        uint256 underlyingAmount = 0;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;
        uint256 ytBeginDate = block.timestamp;
        uint256 expiration = block.timestamp + 60 * 60 * 24 * 7; // one week in seconds

        // give user some ETH and send requests as the user.
        startHoax(address(user));

        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        uint256 amountDepositedUnlocked = 1 ether;
        term.depositUnlocked(amountDepositedUnlocked, 0, 0, address(user));
        uint256 userUnlockedBalance = term.balanceOf(
            UNLOCKED_YT_ID,
            address(user)
        );

        // should fail because amount is more than the user has
        assetIds.push(UNLOCKED_YT_ID);
        assetAmounts.push(userUnlockedBalance + 1);

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
    }

    function testLock_OnlyPrincipalTokens() public {
        uint256 underlyingAmount = 1 ether;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        // block.timestamp starts at 1.  don't use block.timestamp because it is buggy when used
        // with vm.warp() or skip()
        uint256 timeStamp = 1;
        uint256 ytBeginDate = 1;
        uint256 expiration = 10;

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some pts
        (uint256 shares, uint256 value) = term.lock(
            assetIds,
            assetAmounts,
            underlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        // expire the tokens
        skip(expiration);

        // now do a lock with only expired pts
        assetIds.push(expiration); // pt id's are just the expiration
        assetAmounts.push(1 ether);
        timeStamp += 10;
        expiration += 10;
        ytBeginDate = timeStamp;
        (shares, value) = term.lock(
            assetIds,
            assetAmounts,
            0,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        assertEq(value, underlyingAmount, "value not equal to underlying");
        assertEq(shares, value, "shares not equal to value");
        assertEq(
            term.totalSupply(expiration),
            underlyingAmount,
            "totalSupply incorrect"
        );

        uint256 yieldTokenId = (1 << 255) + (ytBeginDate << 128) + expiration;
        uint256 userYts = term.balanceOf(yieldTokenId, address(user));
        uint256 userPts = term.balanceOf(expiration, address(user));
        assertEq(userYts, 1 ether);
        assertEq(userPts, 1 ether);
    }

    function testFailLock_PrincipalTokensNotExpired() public {
        uint256 underlyingAmount = 1 ether;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        // block.timestamp starts at 1.  don't use block.timestamp because it is buggy when used
        // with vm.warp() or skip()
        uint256 timeStamp = 1;
        uint256 ytBeginDate = 1;
        uint256 expiration = 10;

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some pts
        (uint256 shares, uint256 value) = term.lock(
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

        // now do a lock with only expired pts
        assetIds.push(expiration); // pt id's are just the expiration
        assetAmounts.push(1 ether);
        timeStamp += 10;
        expiration += 10;
        ytBeginDate = timeStamp;
        term.lock(
            assetIds,
            assetAmounts,
            0,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );
    }

    function testLock_OnlyYieldTokens() public {
        uint256 underlyingAmount = 1 ether;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        // block.timestamp starts at 1.  don't use block.timestamp because it is buggy when used
        // with vm.warp() or skip()
        uint256 timeStamp = 1;
        uint256 ytBeginDate = 1;
        uint256 expiration = 10_000_000;

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some yts
        (uint256 shares, uint256 value) = term.lock(
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

        // expire the tokens
        skip(expiration);

        // now do a lock with only yts
        uint256 yieldTokenId = (1 << 255) + (ytBeginDate << 128) + expiration;
        assetIds.push(yieldTokenId); // pt id's are just the expiration
        assetAmounts.push(1 ether);
        timeStamp += 10_000_000;
        expiration += 10_000_000;
        ytBeginDate = timeStamp;

        (shares, value) = term.lock(
            assetIds,
            assetAmounts,
            0,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );

        assertEq(value, profit, "value not equal to underlying");
        assertEq(shares, value, "shares not equal to value");
        assertEq(term.totalSupply(expiration), profit, "totalSupply incorrect");

        uint256 newYieldTokenId = (1 << 255) +
            (ytBeginDate << 128) +
            expiration;
        uint256 userYts = term.balanceOf(newYieldTokenId, address(user));
        uint256 userPts = term.balanceOf(expiration, address(user));
        assertEq(userYts, profit);
        assertEq(userPts, profit);
    }

    function testFailLock_YieldTokensNotExpired() public {
        uint256 underlyingAmount = 1 ether;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        // block.timestamp starts at 1.  don't use block.timestamp because it is buggy when used
        // with vm.warp() or skip()
        uint256 timeStamp = 1;
        uint256 ytBeginDate = 1;
        uint256 expiration = 10_000_000;

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some yts
        (uint256 shares, uint256 value) = term.lock(
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

        // now do a lock with only yts
        uint256 yieldTokenId = (1 << 255) + (ytBeginDate << 128) + expiration;
        assetIds.push(yieldTokenId); // pt id's are just the expiration
        assetAmounts.push(1 ether);
        timeStamp += 10_000_000;
        expiration += 10_000_000;
        ytBeginDate = timeStamp;

        term.lock(
            assetIds,
            assetAmounts,
            0,
            hasPreFunding,
            ytDestination,
            ptDestination,
            ytBeginDate,
            expiration
        );
    }

    // tests many combinations of assets.  this is a sanity check and just makes sure that the
    // lock transactions don't fail.
    function testLock_Combinations(
        uint32 numUnderlyingAmount,
        uint32 numPts1,
        uint32 numPts2,
        uint32 numYts1,
        uint32 numYts2,
        uint32 numUnlockedAssets
    ) public {
        // make sure we get at least one value
        vm.assume(
            numUnderlyingAmount > 0 ||
                numPts1 > 0 ||
                numPts2 > 0 ||
                numYts1 > 0 ||
                numYts2 > 0 ||
                numUnlockedAssets > 0
        );

        uint256 underlyingAmount = 1 ether;

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
        token.setBalance(address(user), 10 ether);
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

        uint256 ytBeginDate2 = 1 + 2_500_000;
        uint256 expiration2 = 5_000_000;
        // do another lock to get different pts and yts
        (uint256 shares, uint256 value) = term.lock(
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
        uint256 amountDepositedUnlocked = 1 ether;
        term.depositUnlocked(amountDepositedUnlocked, 0, 0, address(user));
        uint256 userUnlockedBalance = term.balanceOf(
            UNLOCKED_YT_ID,
            address(user)
        );

        // add some profit to the yearn vault
        // this has to happen before we skip ahead in time since the mock vault pro-rates profit
        // from the last time it was added.
        token.approve(address(yearnVault), UINT256_MAX);
        uint256 profit = 0.5 ether;
        yearnVault.report(profit);

        // expire the tokens
        skip(expiration);

        uint256 yieldTokenId = (1 << 255) + (ytBeginDate << 128) + expiration;
        uint256 yieldTokenId2 = (1 << 255) +
            (ytBeginDate2 << 128) +
            expiration2;

        if (numUnlockedAssets > 0) {
            assetIds.push(UNLOCKED_YT_ID);
            console.log("UNLOCKED_YT_ID", UNLOCKED_YT_ID);
            assetAmounts.push(uint256(numUnlockedAssets));
        }

        if (numYts1 > 0) {
            assetIds.push(yieldTokenId);
            console.log("yieldTokenId", yieldTokenId);
            assetAmounts.push(uint256(numYts1));
        }

        if (numYts2 > 0) {
            assetIds.push(yieldTokenId2);
            console.log("yieldTokenId2", yieldTokenId2);
            assetAmounts.push(uint256(numYts2));
        }

        if (numPts1 > 0) {
            assetIds.push(expiration);
            console.log("expiration", expiration);
            assetAmounts.push(uint256(numPts1));
        }

        if (numPts2 > 0) {
            assetIds.push(expiration2);
            console.log("expiration2", expiration2);
            assetAmounts.push(uint256(numPts2));
        }

        (shares, value) = term.lock(
            assetIds,
            assetAmounts,
            numUnderlyingAmount,
            hasPreFunding,
            ytDestination,
            ptDestination,
            15_000_000, // set yt start date in the future to guarantee it starts at current timestamp
            15_000_000
        );

        console.log("shares", shares);
        console.log("value", value);
        console.log("numUnderlyingAmount", numUnderlyingAmount);
        console.log("numPts1", numPts1);
        console.log("numPts2", numPts2);
        console.log("numYts1", numYts1);
        console.log("numYts2", numYts2);
        console.log("numUnlockedAssets", numUnlockedAssets);

        // TODO: figure out a good way to calculate total value.
        // assertApproxEqAbs(
        //     value,
        //     numUnderlyingAmount +
        //         (numUnlockedAssets / 2) +
        //         numPts1 +
        //         numPts2 +
        //         (numYts1 / 2),
        //     (numYts2 / 2),
        //     1000,
        //     "value not equal to assets"
        // );
    }
}
