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

    // test unlocking yield tokens when there is negative interest
    function testUnlock_YieldTokensWithNegativeInterest(uint256 loss) public {
        uint256 underlyingAmount = 1 ether;
        vm.assume(loss <= underlyingAmount);

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

        // remove some assets from the vault
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
    function testUnlock_PrincipalTokensWithNegativeInterest(uint256 loss)
        public
    {
        uint256 underlyingAmount = 1 ether;
        vm.assume(loss > 0 && loss <= underlyingAmount);

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

        // remove some assets from the vault
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
    function testUnlock_UnlockedAssetsWithNegativeInterest(uint256 loss)
        public
    {
        uint256 underlyingAmount = 20 ether;
        vm.assume(loss <= underlyingAmount);

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        token.setBalance(address(user), 20 ether);
        token.approve(address(term), UINT256_MAX);

        // do a deposit to get some unlockedAssets
        (, uint256 shares) = term.depositUnlocked(
            underlyingAmount,
            0,
            0,
            address(user)
        );

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
        assertEq(unlockValue, underlyingAmount - loss);
    }

    // tests many combinations of assets.  this is a sanity check and just makes sure that the
    // unlock transactions don't fail when there is negative interest.
    function testUnlock_CombinationsWithNegativeInterest(
        uint64 numUnlockedAssets,
        uint64 numPts2,
        uint64 numPts1,
        uint64 numYts2,
        uint64 numYts1,
        uint256 loss
    ) public {
        uint256 underlyingAmount = 20 ether;
        // we lock twice with underlyingAmount
        vm.assume(loss <= underlyingAmount * 2);

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

        // experience a loss between 0 and 100%
        yearnVault.reportLoss(loss);

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
