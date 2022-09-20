// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { ERC4626Term } from "contracts/ERC4626Term.sol";

contract ElementTest is Test {
    uint256 public constant YEAR = (365 * 24 * 60 * 60);

    bytes public EMPTY_REVERT = new bytes(0);

    error TestFail();

    // Helper function to create a random address seeded by a string value, also
    // deals and labels the address for easier debugging
    function makeAddress(string memory name) public returns (address addr) {
        addr = vm.addr(uint256(keccak256(abi.encodePacked(name))));
        vm.deal(addr, 100 ether);
        vm.label(addr, name);
    }
}
