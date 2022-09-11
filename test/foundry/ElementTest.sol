// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";

import {ERC4626Term} from "contracts/ERC4626Term.sol";

contract ElementTest is Test {
    uint256 public constant YEAR = (365 * 24 * 60 * 60);

    // TODO Refactor to generalized function when interfaces for variant terms become standardized
    function _underlyingAsUnlockedShares(ERC4626Term term, uint256 underlying) internal returns (uint256) {
        (,,, uint256 impliedUnderlyingReserve) = term.reserveDetails();

        return
            impliedUnderlyingReserve == 0
            ? underlying
            : ((underlying * term.totalSupply(term.UNLOCKED_YT_ID())) / impliedUnderlyingReserve);
    }

    function _mkAddr(string memory name) internal returns (address addr) {
        addr = vm.addr(uint256(keccak256(abi.encodePacked(name))));
        vm.deal(addr, 100 ether);
        vm.label(addr, name);
    }

    function isMessageError(string memory message) internal returns (bool) {
        if (keccak256(abi.encodePacked(message)) != keccak256(abi.encodePacked(""))) {
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
    function shouldExpectFailCase(string memory message, bytes4 selector) internal returns (bool) {
        if (isMessageError(message)) {
            vm.expectRevert(bytes(message));
            return true;
        }
        if (isSelectorError(selector)) {
            vm.expectRevert(selector);
            return true;
        }
        return false;
    }
}
