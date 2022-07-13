// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../libraries/TWAPOracle.sol";

contract MockTWAPOracle is TWAPOracle {
    function initializeBuffer(
        uint256 poolId,
        uint16 maxTime,
        uint16 maxLength
    ) public {
        _initializeBuffer(poolId, maxTime, maxLength);
    }

    function updateBuffer(uint256 poolId, uint224 price) public {
        _updateBuffer(poolId, price);
    }
}
