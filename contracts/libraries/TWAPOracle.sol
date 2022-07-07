// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./CircularBuffers.sol";

contract TWAPOracle is CircularBuffers {
    function _initializeBufferForPool(uint256 poolId, uint16 maxLength)
        internal
    {
        initialize(poolId, maxLength);
    }

    function _updateOracleForPool(uint256 poolId, uint224 price) internal {
        (uint32 blockNumber, , , , ) = readMetadataParsed(poolId);

        // don't add sum twice in one block.  use the first transaction in a block to curb MEV
        // attempts.  Don't require() so calling contracts can complete transactions
        if (block.number < blockNumber) {
            return;
        }

        uint32 timestamp = uint32(block.timestamp);
        (
            uint32 previousTimestamp,
            uint224 previousSum
        ) = readLastSumAndTimestampForPool(poolId);
        (poolId);

        uint224 time = uint224(timestamp - previousTimestamp);
        if (previousTimestamp == 0) {
            time = 1;
        }

        uint224 cumulativeSum = price * time + previousSum;

        uint256 sumAndTimestamp = (uint256(timestamp) << 224) |
            uint256(cumulativeSum);
        addValue(poolId, sumAndTimestamp);

        // TODO: fire event?
    }

    function readSumAndTimestampForPool(uint256 poolId, uint16 index)
        public
        view
        returns (uint32 timestamp, uint224 cumulativeSum)
    {
        uint256 value = getValue(poolId, index);
        cumulativeSum = uint224(value);
        timestamp = uint32(value >> 224);
    }

    function readLastSumAndTimestampForPool(uint256 poolId)
        public
        view
        returns (uint32 timestamp, uint224 cumulativeSum)
    {
        (, , uint16 headIndex, , uint16 bufferLength) = readMetadataParsed(
            poolId
        );

        if (bufferLength == 0) {
            return (0, 0);
        } else {
            return readSumAndTimestampForPool(poolId, headIndex);
        }
    }
}
