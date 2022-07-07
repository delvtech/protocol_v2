// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../libraries/TWAPOracle.sol";

contract MockTWAPOracle is TWAPOracle {
    function initializeBufferForPool(uint256 poolId, uint16 maxLength) public {
        _initializeBufferForPool(poolId, maxLength);
    }

    function updateOracleForPool(uint256 poolId, uint224 price) public {
        _updateOracleForPool(poolId, price);
    }
}
