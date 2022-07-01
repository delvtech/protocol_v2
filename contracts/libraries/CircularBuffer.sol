// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "hardhat/console.sol";

/// A gas efficient library to use uint256[] as a circular buffer.  Assemby is
/// used to to overload the length property with metadata for gas savings.  It
/// is currently configured in the following manner:
/// [bits 255-48] unused
/// [bits 47-32] headIndex - The index of the last item added to the buffer.
/// [bits 31-16] maxLength - The maximum length of the buffer, up to 65534
/// [bits 15-0] bufferLength - The current length of the buffer.  Once this
///             reaches maxLength, headIndex will wrap to zero and items
///             will be overwritten.
library CircularBuffer {
    /// @dev An initialization function for the buffer.  During initialization, the maxLength is
    /// set to the value passed in and the headIndex is set to 0xffff so that it will overflow to
    /// 0 when the first item is added.
    /// @param self A reference to the circular buffer
    /// @param maxLength The maximum number of items in the buffer.  This cannot be unset.
    function initalize(uint256[] storage self, uint16 maxLength) public {
        uint16 headIndex = 0xffff;
        // reserve 0xffff for the head index start position to roll over into zero
        require(maxLength < 0xffff, "max length is 65534");
        uint256 metadata = combineMetadata(headIndex, maxLength, 0);

        assembly {
            // length is stored at position 0 for dynamic arrays
            // we are overloading this to store metadata to be more efficient
            sstore(add(self.offset, 0), metadata)
        }
    }

    /// @dev gets the metadata for the buffer which includes headIndex, maxLength and bufferLength.
    /// @param self A reference to the circular buffer.
    /// @return metadata All metadata encoded into a uint256.
    function readMetadata(uint256[] storage self)
        public
        view
        returns (uint256 metadata)
    {
        assembly {
            metadata := sload(self.offset)
        }
    }

    /// @dev gets the parsed metadata for the buffer which includes headIndex, maxLength and
    /// bufferLength.
    /// @param self A reference to the circular buffer.
    /// @return headIndex maxLength bufferLength as a tuple of uint16's
    function readMetadataParsed(uint256[] storage self)
        public
        view
        returns (
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        )
    {
        uint256 metadata = self.length;
        (headIndex, maxLength, bufferLength) = parseMetadata(metadata);
    }

    /// @dev Internal method that returns parsed metadata.  Returns headIndex, maxLength,
    ///  and bufferLength as a tuple of uint16's
    /// @param buffer A reference to the circular buffer.
    /// @return headIndex maxLength bufferLength as a tuple of uint16's
    function _readMetadataParsed(uint256[] storage buffer)
        private
        view
        returns (
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        )
    {
        uint256 metadata = buffer.length;
        (headIndex, maxLength, bufferLength) = parseMetadata(metadata);
    }

    /// @dev Gets a value in the circular buffer.  `index` must be between 0 and bufferLength.
    /// @param self A reference to the circular buffer.
    /// @param index The index in the buffer of the item to read.  0 < index < bufferLength.
    /// @return value The uint256 value at self[index].
    function getValue(uint256[] storage self, uint16 index)
        public
        view
        returns (uint256 value)
    {
        (, , uint16 bufferLength) = _readMetadataParsed(self);

        // because we overload length for metadata, we need to specifically check the index
        require(index >= 0 && index < bufferLength, "index out of bounds");
        value = self[index];
    }

    // TODO: add this?
    function insertValue(
        uint256[] storage self,
        uint16 index,
        uint256 value
    ) public {}

    // TODO: add this?
    function removeValue(
        uint256[] storage self,
        uint16 index,
        uint256 value
    ) public {}

    /// @dev Adds a value at headIndex to the circular buffer.
    /// @param self A reference to the circular buffer.
    /// @param value The uint256 value to add to the buffer at self[headIndex].
    function addValue(uint256[] storage self, uint256 value) public {
        uint256 metadata = self.length;
        (
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        ) = parseMetadata(metadata);

        if (bufferLength < maxLength) {
            // headIndex initially set to 0xFFFF so that it will overflow to zero
            unchecked {
                headIndex++;
            }
            bufferLength++;
            uint256 newMetadata = combineMetadata(
                headIndex,
                maxLength,
                bufferLength
            );
            _updateBuffer(self, newMetadata, headIndex, value);
        } else if (headIndex < maxLength - 1) {
            headIndex++;
            uint256 newMetadata = combineMetadata(
                headIndex,
                maxLength,
                bufferLength
            );

            _updateBuffer(self, newMetadata, headIndex, value);
        } else if (headIndex == maxLength - 1) {
            headIndex = 0;
            uint256 newMetadata = combineMetadata(
                headIndex,
                maxLength,
                bufferLength
            );

            _updateBuffer(self, newMetadata, headIndex, value);
        }
    }

    /// @dev A private method to update metadata and store a new uint256 value at buffer[index].
    /// @param buffer A reference to the circular buffer.
    /// @param metadata metadata encoded into a uint256 value.
    /// @param index The index in the buffer of the item to read.  0 < index < bufferLength.
    /// @param value The uint256 value to add to the buffer at self[headIndex].
    function _updateBuffer(
        uint256[] storage buffer,
        uint256 metadata,
        uint16 index,
        uint256 value
    ) private {
        assembly {
            // length is stored at position 0 for dynamic arrays
            // we are overloading this to store metadata to be more efficient
            sstore(add(buffer.offset, 0), metadata)
            // store the actual value
            let offset := keccak256(buffer.slot, 32)
            let slot := add(offset, index)
            sstore(slot, value)
        }
    }

    /// @dev An internal method to parse uint256 encoded metadata into it's parts.
    /// @param metadata Metadata encoded in a uint256 value.
    /// @return headIndex maxLength bufferLength
    // [u208 unused][u16 head index][u16 maxLength][u16 length]
    function parseMetadata(uint256 metadata)
        internal
        pure
        returns (
            uint16 headIndex,
            uint16 maxLength,
            uint16 bufferLength
        )
    {
        bufferLength = uint16(metadata);
        maxLength = uint16(metadata >> 16);
        headIndex = uint16(metadata >> 32);
    }

    /// @dev An internal method to combine all metadata parts into a uint256 value.
    /// @param headIndex The index of the last item added to the buffer.
    /// @param maxLength The maximum length of the buffer.
    /// @param bufferLength The current length of the buffer.
    /// @return metadata Metadata encoded in a uint256 value.
    // [u208 unused][u16 head index][u16 maxLength][u16 length]
    function combineMetadata(
        uint16 headIndex,
        uint16 maxLength,
        uint16 bufferLength
    ) internal pure returns (uint256 metadata) {
        metadata =
            (uint256(headIndex) << 32) |
            (uint256(maxLength) << 16) |
            uint256(bufferLength);
    }
}
