// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "hardhat/console.sol";

contract TWAPOracle {
    mapping(uint256 => uint256[]) internal _buffers;

    /// @dev An initialization function for the buffer.  During initialization, the maxLength is
    /// set to the value passed in, minTimeStep and timestamp are set to values for thecurrent block.
    /// 0 when the first item is added.
    /// @param bufferId The ID of the buffer to initialize.
    /// @param maxLength The maximum number of items in the buffer.  This cannot be unset.
    function _initializeBuffer(
        uint256 bufferId,
        uint16 maxTime,
        uint16 maxLength
    ) internal {
        require(maxLength > 0, "min length is 1");

        (, , , uint16 _maxLength, ) = readMetadataParsed(bufferId);
        require(_maxLength == 0, "buffer already initialized");

        uint32 minTimeStep = uint32(maxTime) / uint32(maxLength);
        require(minTimeStep >= 1, "minimum time step is 1");

        uint256 metadata = _combineMetadata(
            minTimeStep,
            uint32(block.timestamp),
            0,
            maxLength,
            0
        );

        uint256[] storage buffer = _buffers[bufferId];
        assembly {
            // length is stored at position 0 for dynamic arrays
            // we are overloading this to store metadata to be more efficient
            sstore(buffer.slot, metadata)
        }
    }

    /// @dev gets the parsed metadata for the buffer which includes headIndex, maxLength and
    /// bufferLength.
    /// @param bufferId The ID of the buffer to read metadata from.
    /// @return minTimeStep timestamp headIndex maxLength bufferLength as a tuple of uint16's
    function readMetadataParsed(uint256 bufferId)
        public
        view
        returns (
            uint32 minTimeStep,
            uint32 timestamp,
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        )
    {
        uint256[] storage buffer = _buffers[bufferId];
        uint256 metadata = buffer.length;

        bufferLength = uint16(metadata);
        // 16
        maxLength = uint16(metadata >> 16);
        // 16 + 16
        headIndex = uint16(metadata >> 32);
        // 16 + 16 + 16
        timestamp = uint32(metadata >> 48);
        // 16 + 16 + 16 + 32
        minTimeStep = uint32(metadata >> 80);
    }

    /// @dev An internal function to update a buffer.  Takes a price, calculates the cumulative
    /// sum, then records it along with the timestamp in the following manner:
    /// [uint32 timestamp][uint224 cumulativeSume]
    /// @param bufferId The ID of the buffer to initialize.
    /// @param price The current price of the token we are tracking a sum for.
    function _updateBuffer(uint256 bufferId, uint224 price) internal {
        (
            uint32 minTimeStep,
            uint32 previousTimestamp,
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        ) = readMetadataParsed(bufferId);

        uint32 timestep = uint32(block.timestamp) - previousTimestamp;
        // Fail silently if enough time has not passed.  We don't reject here because we want
        // calling contracts to try to update often without reverting.
        if (timestep < minTimeStep) {
            return;
        }

        uint256 value;
        uint256[] storage buffer = _buffers[bufferId];

        if (bufferLength != 0) {
            value = buffer[headIndex];
        }

        uint224 time = uint224(uint32(block.timestamp) - previousTimestamp);

        uint224 cumulativeSum;

        // TODO: Normally we calculate the sum by multiplying the price by the amount of time that has
        // elapsed.  Once we are past expiry, we know the price is always 1 so we just multiply
        // by that to make the oracle converge to 1.
        // TODO:  I don' think we actually need to worry about this, probably safe to assume the calling contract
        // will always pass a price of '1' after the expiry anyway.
        // uint224 previousSum;
        // if (block.timestamp < expiry) {
        //     previousSum = uint224(value);
        // } else {
        //     cumulativeSum = 1000000000000000000 * time + previousSum;
        // }
        uint224 previousSum = uint224(value);
        cumulativeSum = price * time + previousSum;

        uint256 sumAndTimestamp = (uint256(block.timestamp) << 224) |
            uint256(cumulativeSum);

        if (bufferLength == 0) {
            // don't increment headIndex if this is the first value added
            headIndex = 0;
        } else {
            headIndex = (headIndex + 1) % maxLength;
        }

        if (bufferLength < maxLength) {
            bufferLength++;
        }

        uint256 metadata = _combineMetadata(
            minTimeStep,
            uint32(block.timestamp),
            headIndex,
            maxLength,
            bufferLength
        );

        // updateBuffer
        assembly {
            // length is stored at position 0 for dynamic arrays
            // we are overloading this to store metadata to be more efficient
            sstore(buffer.slot, metadata)
        }
        buffer[headIndex] = sumAndTimestamp;

        // TODO: fire event?
    }

    /// @dev A public function to read the timestamp&sum value from the specified index and buffer.
    /// @param bufferId The ID of the buffer to initialize.
    /// @param index The index to read a value at.
    /// @return timestamp cumulativeSum 4byte timestamp and 28 byte sum
    function readSumAndTimestampForPool(uint256 bufferId, uint16 index)
        public
        view
        returns (uint32 timestamp, uint224 cumulativeSum)
    {
        (, , , , uint16 bufferLength) = readMetadataParsed(bufferId);

        // TODO: do we need to check this?
        // because we overload length for metadata, we need to specifically check the index
        require(index >= 0 && index < bufferLength, "index out of bounds");

        uint256 value = _buffers[bufferId][index];
        cumulativeSum = uint224(value);
        timestamp = uint32(value >> 224);
    }

    /// @dev An internal method to combine all metadata parts into a uint256 value.
    /// @param headIndex The index of the last item added to the buffer.
    /// @param maxLength The maximum length of the buffer.
    /// @param bufferLength The current length of the buffer.
    /// @return metadata Metadata encoded in a uint256 value.
    // [u144 unused][uint32 minTimeStep][uint32 timestamp][u16 headIndex][u16 maxLength][u16 length]
    function _combineMetadata(
        uint32 minTimeStep,
        uint32 timestamp,
        uint16 headIndex,
        uint16 maxLength,
        uint16 bufferLength
    ) internal pure returns (uint256 metadata) {
        metadata =
            // 16 + 16 + 16 + 32
            (uint256(minTimeStep) << 80) |
            // 16 + 16 + 16
            (uint256(timestamp) << 48) |
            // 16 + 16
            (uint256(headIndex) << 32) |
            // 16
            (uint256(maxLength) << 16) |
            uint256(bufferLength);
    }
}
