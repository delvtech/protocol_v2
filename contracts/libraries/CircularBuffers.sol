// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

/// A gas efficient contract to use uint256 arrays as circular buffers.  Assemby is used to to
/// overload the length property with metadata for gas savings.  It is currently configured in the
/// following manner:
/// uint144 [bits 255-112] unused
/// uint32  [bits 111-80] blockNumber  - The block number the last update was made.
/// uint32  [bits 79-48]  timestamp    - The time in seconds the update was made.
/// uint16  [bits 47-32]  headIndex    - The index of the last item added to the buffer.
/// uint16  [bits 31-16]  maxLength    - The maximum length of the buffer, up to 65534
/// uint16  [bits 15-0]   bufferLength - The current length of the buffer.  Once this
///                       reaches maxLength, headIndex will wrap to zero and items
///                       will be overwritten.
contract CircularBuffers {
    mapping(uint256 => uint256[]) public buffers;

    /// @dev An initialization function for the buffer.  During initialization, the maxLength is
    /// set to the value passed in and the headIndex is set to 0xffff so that it will overflow to
    /// 0 when the first item is added.
    /// @param bufferId The ID of the buffer to initialize.
    /// @param maxLength The maximum number of items in the buffer.  This cannot be unset.
    function initialize(uint256 bufferId, uint16 maxLength) public {
        // reserve 0xffff for the head index start position to roll over into zero
        require(maxLength < 0xffff, "max length is 65534");
        require(maxLength > 0, "min length is 1");

        uint256[] storage buffer = buffers[bufferId];
        (, , , uint16 _maxLength, ) = readMetadataParsed(bufferId);
        require(_maxLength == 0, "buffer already initialized");

        uint16 headIndex = 0xffff;
        uint256 metadata = _combineMetadata(0, 0, headIndex, maxLength, 0);

        assembly {
            // length is stored at position 0 for dynamic arrays
            // we are overloading this to store metadata to be more efficient
            sstore(add(buffer.offset, 0), metadata)
        }
    }

    /// @dev gets the metadata for the buffer which includes headIndex, maxLength and bufferLength.
    /// @param bufferId The ID of the buffer to read metadata from.
    /// @return metadata All metadata encoded into a uint256.
    function readMetadata(uint256 bufferId)
        public
        view
        returns (uint256 metadata)
    {
        uint256[] storage buffer = buffers[bufferId];
        // Note: just reading buffer.length does not work when the array is in a mapping.
        assembly {
            metadata := sload(buffer.offset)
        }
    }

    /// @dev gets the parsed metadata for the buffer which includes headIndex, maxLength and
    /// bufferLength.
    /// @param bufferId The ID of the buffer to read metadata from.
    /// @return blockNumber timestamp headIndex maxLength bufferLength as a tuple of uint16's
    function readMetadataParsed(uint256 bufferId)
        public
        view
        returns (
            uint32 blockNumber,
            uint32 timestamp,
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        )
    {
        uint256 metadata = readMetadata(bufferId);
        (
            blockNumber,
            timestamp,
            headIndex,
            maxLength,
            bufferLength
        ) = _parseMetadata(metadata);
    }

    /// @dev Gets a value in the circular buffer.  `index` must be between 0 and bufferLength.
    /// @param bufferId The ID of the buffer to read a value from.
    /// @param index The index in the buffer of the item to read.  0 < index < bufferLength.
    /// @return value The uint256 value at buffer[index].
    function getValue(uint256 bufferId, uint16 index)
        public
        view
        returns (uint256 value)
    {
        (, , , , uint16 bufferLength) = readMetadataParsed(bufferId);
        uint256[] storage buffer = buffers[bufferId];

        // because we overload length for metadata, we need to specifically check the index
        require(index >= 0 && index < bufferLength, "index out of bounds");
        // Note: just reading buffer[index] does not work since we are overloading the length property
        assembly {
            let offset := keccak256(buffer.offset, 32)
            let slot := add(offset, index)
            value := sload(slot)
        }
    }

    // TODO: add this?
    function insertValue(
        uint256 bufferId,
        uint16 index,
        uint256 value
    ) public {}

    // TODO: add this?
    function removeValue(
        uint256 bufferId,
        uint16 index,
        uint256 value
    ) public {}

    /// @dev Adds a value at headIndex to the circular buffer.
    /// @param bufferId The ID of the buffer to add a value to.
    /// @param value The uint256 value to add to the buffer at buffer[headIndex].
    function addValue(uint256 bufferId, uint256 value) public {
        (
            ,
            ,
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        ) = readMetadataParsed(bufferId);

        if (bufferLength < maxLength) {
            if (headIndex == 0xffff) {
                headIndex = 0;
            } else {
                headIndex++;
            }
            bufferLength++;
            uint256 newMetadata = _combineMetadata(
                uint32(block.number),
                uint32(block.timestamp),
                headIndex,
                maxLength,
                bufferLength
            );

            _updateBuffer(bufferId, newMetadata, headIndex, value);
        } else if (headIndex < maxLength - 1) {
            headIndex++;
            uint256 newMetadata = _combineMetadata(
                uint32(block.number),
                uint32(block.timestamp),
                headIndex,
                maxLength,
                bufferLength
            );

            _updateBuffer(bufferId, newMetadata, headIndex, value);
        } else if (headIndex == maxLength - 1) {
            headIndex = 0;
            uint256 newMetadata = _combineMetadata(
                uint32(block.number),
                uint32(block.timestamp),
                headIndex,
                maxLength,
                bufferLength
            );

            _updateBuffer(bufferId, newMetadata, headIndex, value);
        }
    }

    /// @dev A private method to update metadata and store a new uint256 value at buffer[index].
    /// Metadata is stored in the length property of each buffer to save on gas when writing to
    /// storage.  By doing this we can only incur the cost of one write to storage.
    /// @param bufferId The ID of the buffer to update.
    /// @param metadata metadata encoded into a uint256 value.
    /// @param index The index in the buffer of the item to read.  0 < index < bufferLength.
    /// @param value The uint256 value to add to the buffer at buffer[headIndex].
    function _updateBuffer(
        uint256 bufferId,
        uint256 metadata,
        uint16 index,
        uint256 value
    ) private {
        uint256[] storage buffer = buffers[bufferId];
        assembly {
            // length is stored at position 0 for dynamic arrays
            // we are overloading this to store metadata to be more efficient
            sstore(add(buffer.offset, 0), metadata)
            // store the actual value

            let offset := keccak256(buffer.offset, 32)
            let slot := add(offset, index)
            sstore(slot, value)
        }
    }

    /// @dev An internal method to parse uint256 encoded metadata into it's parts.
    /// @param metadata Metadata encoded in a uint256 value.
    /// @return blockNumber timestamp headIndex maxLength bufferLength
    // [u144 unused][uint32 blockNumber][uint32 timestamp][u16 headIndex][u16 maxLength][u16 length]
    function _parseMetadata(uint256 metadata)
        internal
        pure
        returns (
            uint32 blockNumber,
            uint32 timestamp,
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        )
    {
        bufferLength = uint16(metadata);
        // 16
        maxLength = uint16(metadata >> 16);
        // 16 + 16
        headIndex = uint16(metadata >> 32);
        // 16 + 16 + 16
        timestamp = uint32(metadata >> 48);
        // 16 + 16 + 16 + 32
        blockNumber = uint32(metadata >> 80);
    }

    /// @dev An internal method to combine all metadata parts into a uint256 value.
    /// @param headIndex The index of the last item added to the buffer.
    /// @param maxLength The maximum length of the buffer.
    /// @param bufferLength The current length of the buffer.
    /// @return metadata Metadata encoded in a uint256 value.
    // [u144 unused][uint32 blockNumber][uint32 timestamp][u16 headIndex][u16 maxLength][u16 length]
    function _combineMetadata(
        uint32 blockNumber,
        uint32 timestamp,
        uint16 headIndex,
        uint16 maxLength,
        uint16 bufferLength
    ) internal pure returns (uint256 metadata) {
        metadata =
            // 16 + 16 + 16 + 32
            (uint256(blockNumber) << 80) |
            // 16 + 16 + 16
            (uint256(timestamp) << 48) |
            // 16 + 16
            (uint256(headIndex) << 32) |
            // 16
            (uint256(maxLength) << 16) |
            uint256(bufferLength);
    }
}
