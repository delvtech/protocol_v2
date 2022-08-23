// SPDX-License-Identifier: UNLICENSED
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
    // test unlocking yield tokens when there is negative interest
    function testUnlock_YieldTokensWithNegativeInterest() public {
        uint256 underlyingAmount = 1 ether;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        // block.timestamp starts at 1.  don't use block.timestamp because it is buggy when used
        // with vm.warp() or skip()
        uint256 ytBeginDate = 1;
        uint256 expiration = 10_000_000;

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some yts
        (uint256 shares, ) = term.lock(
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

        uint256 loss = 0.5 ether;
        yearnVault.reportLoss(loss);

        // expire the tokens
        skip(expiration);

        // now unlock yts
        uint256 yieldTokenId = (1 << 255) + (ytBeginDate << 128) + expiration;
        assetIds.push(yieldTokenId);
        assetAmounts.push(shares);

        uint256 ytUnlockValue = term.unlock(
            address(user),
            assetIds,
            assetAmounts
        );

        // since there was negative interest, this should be zero.
        assertEq(ytUnlockValue, 0);
    }

    // test unlocking principal tokens when there is negative interest
    function testUnlock_PrincipalTokensWithNegativeInterest() public {
        uint256 underlyingAmount = 1 ether;

        address ytDestination = address(user);
        address ptDestination = address(user);
        bool hasPreFunding = false;

        // block.timestamp starts at 1.  don't use block.timestamp because it is buggy when used
        // with vm.warp() or skip()
        uint256 ytBeginDate = 1;
        uint256 expiration = 10_000_000;

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        // do a lock to get some yts
        (uint256 shares, ) = term.lock(
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

        uint256 loss = 0.5 ether;
        yearnVault.reportLoss(loss);

        // expire the tokens
        skip(expiration);

        // now lets add some pts to unlock, which should have 1/2 their value still
        assetIds.push(expiration);
        assetAmounts.push(shares);

        uint256 ptUnlockValue = term.unlock(
            address(user),
            assetIds,
            assetAmounts
        );

        // value should be everything that's left
        assertEq(ptUnlockValue, underlyingAmount - loss);
    }

    // test unlocking unlocked assets when there is negative interest
    function testUnlock_UnlockedAssetsWithNegativeInterest() public {
        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), 20 ether);
        token.approve(address(term), UINT256_MAX);

        // do a deposit to get some unlockedAssets
        // get some unlocked assets as well
        uint256 amountDepositedUnlocked = 20 ether;
        (, uint256 shares) = term.depositUnlocked(
            amountDepositedUnlocked,
            0,
            0,
            address(user)
        );

        uint256 loss = 0.5 ether;
        yearnVault.reportLoss(loss);

        // now lets add some pts to unlock, which should have 1/2 their value still
        assetIds.push(UNLOCKED_YT_ID);
        assetAmounts.push(uint256(shares));

        uint256 unlockValue = term.unlock(
            address(user),
            assetIds,
            assetAmounts
        );

        // value should be everything that's left
        assertEq(unlockValue, amountDepositedUnlocked - loss);
    }
}
