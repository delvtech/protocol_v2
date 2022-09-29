// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "contracts/LP.sol";
import "contracts/interfaces/IERC20.sol";

contract MockLP is LP {
    uint256 _lpShares;

    constructor(
        IERC20 _token,
        ITerm _term,
        bytes32 _linkerCodeHash,
        address _factory
    ) LP(_token, _term, _linkerCodeHash, _factory) {}

    function setLpShares(uint256 value) public {
        _lpShares = value;
    }

    function setTotalSupply(uint256 poolId, uint256 value) public {
        totalSupply[poolId] = value;
    }

    function setShareReserves(uint256 poolId, uint128 value) public {
        reserves[poolId].shares = value;
    }

    function setBondReserves(uint256 poolId, uint128 value) public {
        reserves[poolId].bonds = value;
    }

    event DepositFromShares();

    // use this to stub calls to _depositFromShares
    function _depositFromShares(
        uint256 poolId,
        uint256 currentShares,
        uint256 currentBonds,
        uint256 depositedShares,
        uint256 pricePerShare,
        address to
    ) internal override returns (uint256) {
        emit DepositFromShares();
        return _lpShares;
    }

    // use this to test the actual _depositFromShares method
    function depositFromSharesExternal(
        uint256 poolId,
        uint256 currentShares,
        uint256 currentBonds,
        uint256 depositedShares,
        uint256 pricePerShare,
        address to
    ) external returns (uint256) {
        return
            super._depositFromShares(
                poolId,
                currentShares,
                currentBonds,
                depositedShares,
                pricePerShare,
                to
            );
    }
}
