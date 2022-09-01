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

    function _getID(
        uint256 isYT,
        uint256 start,
        uint256 end
    ) internal returns (uint256) {
        return ((isYT << (255 + start)) << (128 + end));
    }

    // Checks for reversion cases on the token id
    function testOutOfBoundYT() public {
        // Check that it must be a YT
        term.convertYT(_getID(0, 10, 11), 0, address(user), true);
        vm.expectRevert(ElementError.NotAYieldTokenId);
        // zero end
        term.convertYT(_getID(1, 10, 0), 0, address(user), true);
        vm.expectRevert(ElementError.ExpirationDateMustBeNonZero);
        // zero start
        term.convertYT(_getID(1, 0, 11), 0, address(user), true);
        vm.expectRevert(ElementError.StartDateMustBeNonZero);
        // expired
        term.convertYT(
            _getID(1, 10, block.timestamp - 1),
            0,
            address(user),
            true
        );
        vm.expectRevert(ElementError.TermExpired);
    }
}
