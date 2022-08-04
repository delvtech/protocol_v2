// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/Term.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "contracts/interfaces/IERC20.sol";

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract MockTerm is Term {
    uint256 public underlyingReserve;
    uint256 public vaultShareReserve;

    constructor(
        bytes32 _linkerCodeHash,
        address _factory,
        IERC20 _token,
        address _owner
    ) Term(_linkerCodeHash, _factory, _token, _owner) {} // solhint-disable-line no-empty-blocks

    function mint(
        uint256 tokenID,
        address to,
        uint256 amount
    ) public {
        _mint(tokenID, to, amount);
        uint256 expiry = uint256(uint128(tokenID));
        sharesPerExpiry[expiry] += amount;
    }

    function setSharesPerExpiry(uint256 expiry, uint256 amount) public {
        sharesPerExpiry[expiry] = amount;
    }

    function _deposit(ShareState state)
        internal
        override
        returns (uint256 shares, uint256 value)
    {
        return
            state == ShareState.Locked ? _depositLocked() : _depositUnlocked();
    }

    function _depositLocked()
        internal
        returns (uint256 shares, uint256 userSuppliedUnderlying)
    {} // solhint-disable-line no-empty-blocks

    // none goes to a vault, we just keep track
    function _depositUnlocked()
        internal
        returns (uint256 shares, uint256 userSuppliedUnderlying)
    {
        uint256 termTokenBalance = token.balanceOf(address(this));
        userSuppliedUnderlying = termTokenBalance - underlyingReserve;

        if (underlyingReserve == 0) {
            shares = userSuppliedUnderlying;
        } else {
            shares =
                (userSuppliedUnderlying * totalSupply[UNLOCKED_YT_ID]) /
                underlyingReserve;
        }

        underlyingReserve += token.balanceOf(address(this));
    }

    function _underlying(uint256 shares, ShareState state)
        internal
        view
        override
        returns (uint256)
    {
        if (state == ShareState.Locked) {
            // just return 1-1 shares for underlying for lock right now
            // mock interest later
            return shares;
        } else {
            return (shares * underlyingReserve) / totalSupply[UNLOCKED_YT_ID];
        }
    }

    /// @return the amount produced
    function _withdraw(
        uint256,
        address,
        ShareState
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _convert(ShareState, uint256)
        internal
        pure
        override
        returns (uint256)
    {
        return 0;
    }
}

contract TermTest is Test {
    ForwarderFactory public ff;
    MockTerm public term;
    MockERC20Permit public token;
    User public user;

    function setUp() public {
        ff = new ForwarderFactory();
        token = new MockERC20Permit("Test Token", "tt", 18);
        user = new User();
        term = new MockTerm(
            ff.ERC20LINK_HASH(),
            address(ff),
            token,
            address(user)
        );
    }

    function testDeploy() public {
        console2.log("term address %s", address(term));
        assertEq(
            address(0xf5a2fE45F4f1308502b1C136b9EF8af136141382),
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

        assertEq(value, underlyingAmount);
        assertEq(shares, value);
        assertEq(term.totalSupply(term.UNLOCKED_YT_ID()), 1 ether);
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

        vm.expectRevert("Not expired");
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

        (uint256 shares, uint256 value) = term.depositUnlocked(
            underlyingAmount,
            ptAmount,
            ptExpiry,
            destination
        );

        console2.log("underlyingAmount %s", underlyingAmount);
        console2.log("value %s", value);
        console2.log("shares %s", shares);
        console2.log(
            "user balance unlocked yts %s",
            term.balanceOf(term.UNLOCKED_YT_ID(), address(user))
        );

        assertEq(shares, underlyingAmount + ptAmount);
        assertEq(term.totalSupply(term.UNLOCKED_YT_ID()), 1 ether);
        // user should not have any pts left
        assertEq(term.balanceOf(ptExpiry, address(user)), 0);
        // should have all yts now
        assertEq(term.balanceOf(term.UNLOCKED_YT_ID(), address(user)), 1 ether);
    }
}
