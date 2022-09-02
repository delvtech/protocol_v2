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

        vm.prank(address(user));
        token.approve(address(term), UINT256_MAX);
    }

    function _getID(
        uint256 isYT,
        uint256 start,
        uint256 end
    ) internal pure returns (uint256) {
        return ((isYT << 255) + (start << 128) + end);
    }

    // Checks for reversion cases on the token id
    function testFailOutOfBoundYT() public {
        // Check that it must be a YT
        vm.expectRevert(ElementError.NotAYieldTokenId.selector);
        term.convertYT(_getID(0, 10, 11), 0, address(user), true);
        // zero end
        vm.expectRevert(ElementError.ExpirationDateMustBeNonZero.selector);
        term.convertYT(_getID(1, 10, 0), 0, address(user), true);
        // zero start
        vm.expectRevert(ElementError.StartDateMustBeNonZero.selector);
        term.convertYT(_getID(1, 0, 11), 0, address(user), true);
        // same block start
        vm.expectRevert(ElementError.InvalidStart.selector);
        term.convertYT(_getID(1, block.timestamp, 11), 0, address(user), true);
        // expired
        vm.expectRevert(ElementError.TermExpired.selector);
        term.convertYT(
            _getID(1, 10, block.timestamp - 1),
            0,
            address(user),
            true
        );
    }

    function _deposit(
        address who,
        uint256 amount,
        uint256 start,
        uint256 end
    ) internal {
        token.mint(who, amount);
        vm.prank(who);
        term.lock(assetIds, sharesList, amount, false, who, who, start, end);
        vm.stopPrank();
    }

    // Tests a case where a user deposits, earns interest then converts and withdraws
    function testSimpleConvertNoCompound() public {
        // Simple setup for the user
        _deposit(address(user), 10e6, 1, 10);
        token.mint(address(yearnVault), 5e6);
        vm.warp(5);

        vm.prank(address(user));
        term.convertYT(_getID(1, 1, 10), 5e6, address(user), false);
        uint256 interest = token.balanceOf(address(user));
        assertApproxEqAbs(interest, 25e5, 1);
        uint256 balanceYT = term.balanceOf(_getID(1, 5, 10), address(user));
        assertEq(balanceYT, 5e6);

        // Now to check price consistency we forward and redeem
        vm.warp(11);
        assetIds.push(_getID(1, 1, 10));
        // small rounding error here
        sharesList.push(5e6 - 1);

        vm.prank(address(user));
        term.unlock(address(user), assetIds, sharesList);

        assertApproxEqAbs(token.balanceOf(address(user)), 5e6, 2);

        assetIds.pop();
        sharesList.pop();
        assetIds.push(_getID(0, 0, 10));
        sharesList.push(10e6);
        vm.prank(address(user));
        term.unlock(address(user), assetIds, sharesList);

        assertApproxEqAbs(token.balanceOf(address(user)), 15e6, 2);
        assertEq(term.sharesPerExpiry(10), 0);

        assetIds.pop();
        sharesList.pop();
        assetIds.push(_getID(1, 5, 10));
        sharesList.push(balanceYT);
        vm.prank(address(user));
        term.unlock(address(user), assetIds, sharesList);

        assertApproxEqAbs(token.balanceOf(address(user)), 15e6, 2);
    }

    // Tests a case where a user deposits, earns interest then converts and withdraws
    function testSimpleConvertCompound() public {
        // Simple setup for the user
        _deposit(address(user), 10e6, 1, 10);
        token.mint(address(yearnVault), 5e6);
        vm.warp(5);

        uint256 sharesPerExpiryBefore = term.sharesPerExpiry(10);
        vm.prank(address(user));
        term.convertYT(_getID(1, 1, 10), 5e6, address(user), true);

        assertEq(sharesPerExpiryBefore, term.sharesPerExpiry(10));

        uint256 ptBalance = term.balanceOf(_getID(0, 0, 10), address(user));
        // 10 from first deposit 2.5 from redeposit
        assertApproxEqAbs(ptBalance, 125e5, 1);
        uint256 balanceYT = term.balanceOf(_getID(1, 5, 10), address(user));
        // 5 from the redeposit and 2.5 from redeposit
        assertEq(balanceYT, 75e5);

        // Now to check price consistency we forward and redeem
        vm.warp(11);
        assetIds.push(_getID(1, 1, 10));
        // small rounding error here
        sharesList.push(5e6 - 1);

        vm.prank(address(user));
        term.unlock(address(user), assetIds, sharesList);

        assertApproxEqAbs(token.balanceOf(address(user)), 25e5, 2);

        assetIds.pop();
        sharesList.pop();
        assetIds.push(_getID(0, 0, 10));
        sharesList.push(125e5);
        vm.prank(address(user));
        term.unlock(address(user), assetIds, sharesList);

        assertApproxEqAbs(token.balanceOf(address(user)), 15e6, 2);
        assertEq(term.sharesPerExpiry(10), 0);

        assetIds.pop();
        sharesList.pop();
        assetIds.push(_getID(1, 5, 10));
        sharesList.push(balanceYT);
        vm.prank(address(user));
        term.unlock(address(user), assetIds, sharesList);

        assertApproxEqAbs(token.balanceOf(address(user)), 15e6, 2);
    }
}
