// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import "contracts/ForwarderFactory.sol";
import "contracts/mocks/MockCompoundV3Term.sol";
import "contracts/mocks/MockCompoundV3.sol";
import "contracts/mocks/MockERC20Permit.sol";

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract CompoundV3TermTest is Test {
    MockCompoundV3Term public term;
    MockCompoundV3 public compound;
    MockERC20Permit public usdc;
    User public user;

    function setUp() public {
        user = new User();
        usdc = new MockERC20Permit("USDC Coin", "USDC", 6);
        ForwarderFactory forwarderFactory = new ForwarderFactory();
        compound = new MockCompoundV3(IERC20(usdc));

        term = new MockCompoundV3Term(
            address(compound), // compound address
            forwarderFactory.ERC20LINK_HASH(), // linker hash
            address(forwarderFactory), // factory address
            100_000e6, // max reserve
            address(this) // owner
        );

        vm.label(address(term), "MockCompoundV3Term");
    }

    // -------------------  _setReserves unit tests   ------------------ //

    function test__setReserves() public {
        term.setReservesExternal(1, 0);

        uint128 underlyingReserve = term.getUnderlyingReserve();
        uint128 yieldShareReserve = term.getYieldShareReserve();
        assertEq(underlyingReserve, 1);
        assertEq(yieldShareReserve, 0);
    }
}
