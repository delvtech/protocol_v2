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
import "contracts/libraries/Errors.sol";

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract TermTest is Test {
    ForwarderFactory public ff;
    MockYieldAdapter public term;
    MockERC20Permit public token;
    MockERC20YearnVault public yearnVault;
    User public user;

    uint256[] public assetIds;
    uint256[] public sharesList;

    function setUp() public {
        ff = new ForwarderFactory();
        token = new MockERC20Permit("Test Token", "tt", 18);
        user = new User();
        yearnVault = new MockERC20YearnVault(address(token));
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
    }

    function testDeploy() public {
        assertEq(
            address(0x42997aC9251E5BB0A61F4Ff790E5B991ea07Fd9B),
            address(term)
        );
    }

    function testDepositUnlocked_OnlyUnderlying() public {
        uint256 underlyingAmount = 1 ether;
        uint256 ptAmount = 0;
        uint256 ptExpiry = 1000;
        address destination = address(user);

        // give user some ETH and send requests as the user.
        startHoax(address(user));

        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        (uint256 shares, uint256 value) = term.depositUnlocked(
            underlyingAmount,
            ptAmount,
            ptExpiry,
            destination
        );

        // MockYieldAdapter returns twice the value for depositing unlocked assets
        assertEq(value, 2 * underlyingAmount);
        // MockYieldAdapter returns twice the value for depositing unlocked assets
        assertEq(value, 2 * shares);
        // MockYieldAdapter returns twice the value for depositing unlocked assets
        assertEq(term.totalSupply(term.UNLOCKED_YT_ID()), 2 ether);
    }

    function testDepositUnlocked_NotExpired() public {
        uint256 underlyingAmount = 1 ether;
        uint256 ptAmount = 1 ether;
        uint256 ptExpiry = 1000;
        address destination = address(user);

        // give user some ETH and send requests as the user.
        startHoax(address(user));

        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        vm.expectRevert(ElementError.TermExpired.selector);
        term.depositUnlocked(underlyingAmount, ptAmount, ptExpiry, destination);
    }

    // try to redeem expired pt, even though the caller has none.  causes a div by zero error.
    function testFailDepositUnlocked_NoPt() public {
        uint256 underlyingAmount = 1 ether;
        uint256 ptAmount = 1 ether;
        uint256 ptExpiry = 1000;
        address destination = address(user);

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        // jump to timestamp 2001, block number 2;
        vm.warp(2000);
        vm.roll(2);

        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        // FAIL. Reason: Division or modulo by 0
        term.depositUnlocked(underlyingAmount, ptAmount, ptExpiry, destination);
    }

    // try to redeem expired pt, even though the caller doesn't have enough.
    function testFailDepositUnlocked_NotEnoughPt() public {
        uint256 underlyingAmount = 1 ether;
        uint256 ptAmount = 1 ether;
        uint256 ptExpiry = 1000;
        address destination = address(user);

        // give user 1 wei less than we try to redeem
        term.mint(ptExpiry, address(user), 1 ether - 1);

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        // jump to timestamp 2001, block number 2;
        vm.warp(2000);
        vm.roll(2);

        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        // FAIL. Reason: Arithmetic over/underflow
        term.depositUnlocked(underlyingAmount, ptAmount, ptExpiry, destination);
    }

    // user has both underlying and pt
    function testDepositUnlocked_UnderlyingAndPt() public {
        uint256 underlyingAmount = 1 ether;
        uint256 ptAmount = 1 ether;
        uint256 ptExpiry = 1000;
        address destination = address(user);

        // mint enough pt to redeem
        term.mint(ptExpiry, address(user), ptAmount);
        term.setSharesPerExpiry(ptExpiry, ptAmount);

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        // jump to timestamp 2001, block number 2;
        vm.warp(2000);
        vm.roll(2);

        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        (uint256 shares, ) = term.depositUnlocked(
            underlyingAmount,
            ptAmount,
            ptExpiry,
            destination
        );

        assertEq(shares, underlyingAmount + ptAmount);

        // user should not have any pts left
        assertEq(term.balanceOf(ptExpiry, address(user)), 0);
        // should have all yts now, both user shares and total supply = 2.5 ether
        // MockYieldAdapter returns 2x for depositing unlocked assets and 0.5x for releasing the pts.
        assertEq(
            term.balanceOf(term.UNLOCKED_YT_ID(), address(user)),
            2.5 ether
        );
        // MockYieldAdapter returns 2x for depositing underlying amount and 0.5x for releasing the pts.
        assertEq(term.totalSupply(term.UNLOCKED_YT_ID()), 2.5 ether);

        uint256 unlockYtId = term.UNLOCKED_YT_ID();
        assetIds.push(unlockYtId);
        sharesList.push(1 ether);
        uint256 redeemValue = term.unlock(address(user), assetIds, sharesList);
    }

    function testDepositUnlocked_OnlyPt() public {
        uint256 underlyingAmount = 0;
        uint256 ptAmount = 1 ether;
        uint256 ptExpiry = 1000;
        address destination = address(user);

        // mint enough pt to redeem
        term.mint(ptExpiry, address(user), ptAmount);
        term.setSharesPerExpiry(ptExpiry, ptAmount);

        // give user some ETH and send requests as the user.
        startHoax(address(user));
        // jump to timestamp 2001, block number 2;
        vm.warp(2000);
        vm.roll(2);

        token.setBalance(address(user), 10 ether);
        token.approve(address(term), UINT256_MAX);

        (uint256 shares, uint256 value) = term.depositUnlocked(
            underlyingAmount,
            ptAmount,
            ptExpiry,
            destination
        );

        assertEq(shares, underlyingAmount + ptAmount);
        // MockYieldAdapter returns 0.5x for releasing pts
        assertEq(term.totalSupply(term.UNLOCKED_YT_ID()), 0.5 ether);
        // user should not have any pts left
        assertEq(term.balanceOf(ptExpiry, address(user)), 0);
        // should have all yts now
        // MockYieldAdapter returns 0.5x for releasing pts
        assertEq(
            term.balanceOf(term.UNLOCKED_YT_ID(), address(user)),
            0.5 ether
        );
    }
}
