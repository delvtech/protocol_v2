// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { ERC4626Term } from "contracts/ERC4626Term.sol";

contract ElementTest is Test {
    uint256 public constant YEAR = (365 * 24 * 60 * 60);

    bytes public constant EMPTY_REVERT = new bytes(0);

    error ExpectedFailingTestPasses(bytes expected);
    error ExpectedDifferentFailureReason(bytes err, bytes expected);
    error ExpectedDifferentFailureReasonString(string err, string expected);
    error ExpectedPassingTestFails(bytes err);
    error InvalidTestCaseLength(uint256 expected, uint256 actual);

    // Helper function to create a random address seeded by a string value, also
    // deals and labels the address for easier debugging
    function makeAddress(string memory name) public returns (address addr) {
        addr = vm.addr(uint256(keccak256(abi.encodePacked(name))));
        vm.deal(addr, 100 ether);
        vm.label(addr, name);
    }

    function _validateTestCaseLength(
        uint256[] memory testCase,
        uint256 expectedLen
    ) internal pure {
        if (testCase.length != expectedLen) {
            revert InvalidTestCaseLength({
                expected: expectedLen,
                actual: testCase.length
            });
        }
    }

    // https://book.getfoundry.sh/cheatcodes/expect-emit?highlight=expectEmi#expectemit
    // The typical `expectEmit` function as specified in the documentation will
    // when always validate topic0 and optionally topic1, topic2, topic3 and
    // the event data (non-indexed args);
    // In the event those options are set to true but the event in question does
    // not contain those arguments, then those checks are not considered
    // regardless. Example:
    //
    // SomeEvent(uint256 indexed arg1);
    //
    // - vm.expectEmit(true, false, false, false); <- Docs suggestion
    // - vm.expectEmit(true, true, true, true);
    //
    // Both of these will check for a "SomeEvent" event with a uint256 topic1
    //
    // Therefore it makes sense that for any event we wish to expect for, that
    // the strictest settings be used by setting all options to true as we lose
    // nothing by being less specific and it is less developer overhead to have
    // to check whether a certain event argument is indexed or not
    function expectStrictEmit() public {
        vm.expectEmit(true, true, true, true);
    }
}
