// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

contract TestDynamicArray {
    uint256[] public list;
    mapping(uint256 => uint256[]) public lists;

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

    function addValueHighLevel(
        uint256 metadata,
        uint256 index,
        uint256 value
    ) public {
        assembly {
            // length is stored at position 0 for dynamic arrays
            // we are overloading this to store metadata to be more efficient
            sstore(add(list.offset, 0), metadata)
        }
        list[index] = value;
    }

    function readValue(uint256 metadata, uint256 index)
        public
        returns (uint256 value)
    {
        assembly {
            // read the actual value at the index
            let offset := keccak256(list.slot, 1)
            let slot := add(offset, index)
            value := sload(slot)
        }
    }

    function addValueNoKeccak(
        uint256 metadata,
        uint256 index,
        uint256 value
    ) public {
        assembly {
            // length is stored at position 0 for dynamic arrays
            // we are overloading this to store metadata to be more efficient
            sstore(add(list.offset, 0), metadata)
            // store the actual value at the index
            let offset := add(list.offset, 32)
            let slot := add(list.offset, offset)
            sstore(slot, value)
        }
    }

    function readValueNoKeccak(uint256 index) public returns (uint256 value) {
        assembly {
            // read the actual value at the index
            let offset := add(index, 1)
            let slot := add(list.offset, offset)
            value := sload(slot)
        }
    }

    function addMappedValue(
        uint256 listId,
        uint256 metadata,
        uint256 index,
        uint256 value
    ) public {
        assembly {
            // length is stored at position 0 for dynamic arrays
            // we are overloading this to store metadata to be more efficient
            sstore(add(list.offset, 0), metadata)
            // store the actual value at the index
            let offset := keccak256(list.slot, 1)
            let slot := add(offset, index)
            sstore(slot, value)
        }
    }

    function readMappedValue(
        uint256 listId,
        uint256 metadata,
        uint256 index
    ) public returns (uint256 value) {
        assembly {
            // read the actual value at the index
            let offset := keccak256(list.slot, 1)
            let slot := add(offset, index)
            value := sload(slot)
        }
    }
}
