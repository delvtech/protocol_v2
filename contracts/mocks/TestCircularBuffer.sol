// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../libraries/CircularBuffer.sol";

contract TestCircularBuffer {
    using CircularBuffer for uint256[];

    uint256[] internal _buffer;

    constructor(uint8 _maxLength) {
        _buffer.initalize(_maxLength);
    }

    function addValue(uint256 value) public {
        _buffer.addValue(value);
    }

    function getValue(uint16 index) public view returns (uint256 value) {
        value = _buffer.getValue(index);
    }

    function readMetadata() public view returns (uint256 metadata) {
        metadata = _buffer.readMetadata();
    }
}
