// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { ERC4626Term } from "contracts/ERC4626Term.sol";

contract ElementTest is Test {
    uint256 public constant YEAR = (365 * 24 * 60 * 60);

    // Helper function to create a random address seeded by a string value, also
    // deals and labels the address for easier debugging
    function makeAddress(string memory name) public returns (address addr) {
        addr = vm.addr(uint256(keccak256(abi.encodePacked(name))));
        vm.deal(addr, 100 ether);
        vm.label(addr, name);
    }

    function isMessageError(string memory message) internal returns (bool) {
        if (
            keccak256(abi.encodePacked(bytes(message))) !=
            keccak256(abi.encodePacked(""))
        ) {
            return true;
        }
        return false;
    }

    function isSelectorError(bytes4 selector) internal returns (bool) {
        if (selector != bytes4(0)) {
            return true;
        }
        return false;
    }

    // abstracts error validation for unit testing
    function expectRevert(string memory message, bytes4 selector)
        public
        returns (bool)
    {
        // generic error
        if (
            keccak256(abi.encodePacked(message)) ==
            keccak256(abi.encodePacked("EvmError: Revert"))
        ) {
            vm.expectRevert();
        } else if (isMessageError(message)) {
            vm.expectRevert(bytes(message));
        } else if (isSelectorError(selector)) {
            vm.expectRevert(selector);
        }
    }
}
