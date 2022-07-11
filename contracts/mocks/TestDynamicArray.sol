// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

contract TestDynamicArray {
    uint256[] public list;

    function readMetadata() public view returns (uint256) {
        return list.length;
    }

    function addValue(
        uint256 metadata,
        uint256 index,
        uint256 value
    ) public {
        assembly {
            // length is stored at position 0 for dynamic arrays
            // we are overloading this to store metadata to be more efficient
            sstore(add(list.offset, 0), metadata)
            // store the actual value at the index
            let offset := keccak256(list.slot, 32)
            let slot := add(offset, index)
            sstore(slot, value)
        }
    }
}
