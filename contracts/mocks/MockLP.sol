// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "contracts/LP.sol";
import "contracts/interfaces/IERC20.sol";

contract MockLP is LP {
    constructor(
        IERC20 _token,
        ITerm _term,
        bytes32 _linkerCodeHash,
        address _factory
    ) LP(_token, _term, _linkerCodeHash, _factory) {} // solhint-disable-line no-empty-blocks

    function setTotalSupply(uint256 poolId, uint256 value) public {
        totalSupply[poolId] = value;
    }

    function setShareReserves(uint256 poolId, uint128 value) public {
        reserves[poolId].shares = value;
    }

    function setBondReserves(uint256 poolId, uint128 value) public {
        reserves[poolId].bonds = value;
    }

    function setLpBalance(
        uint256 poolId,
        address owner,
        uint256 value
    ) public {
        _mint(poolId, owner, value);
    }

    // ##############################
    // ###   _depositFromShares   ###
    // ##############################
    event DepositFromShares(
        uint256 poolId,
        uint256 currentShares,
        uint256 currentBonds,
        uint256 depositedShares,
        uint256 pricePerShare,
        address to
    );

    uint256 internal _depositFromSharesReturnValue;

    function setDepositFromSharesReturnValue(uint256 value) public {
        _depositFromSharesReturnValue = value;
    }

    // use this to stub calls to _depositFromShares
    function _depositFromShares(
        uint256 poolId,
        uint256 currentShares,
        uint256 currentBonds,
        uint256 depositedShares,
        uint256 pricePerShare,
        address to
    ) internal override returns (uint256) {
        emit DepositFromShares(
            poolId,
            currentShares,
            currentBonds,
            depositedShares,
            pricePerShare,
            to
        );
        return _depositFromSharesReturnValue;
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

    // #############################
    // ###   _withdrawToShares   ###
    // #############################
    event WithdrawToShares(uint256 poolId, uint256 amount, address source);

    uint256 internal _withdrawSharesValue;
    uint256 internal _withdrawBondsValue;

    function setWithdrawToSharesReturnValues(
        uint256 sharesValue,
        uint256 bondsValue
    ) public {
        _withdrawSharesValue = sharesValue;
        _withdrawBondsValue = bondsValue;
    }

    // use this to stub calls to _withdrawFromShares
    function _withdrawToShares(
        uint256 poolId,
        uint256 amount,
        address source
    ) internal override returns (uint256, uint256) {
        emit WithdrawToShares(poolId, amount, source);
        return (_withdrawSharesValue, _withdrawBondsValue);
    }

    // use this to test the actual _withdrawToShares method
    function withdrawToSharesExternal(
        uint256 poolId,
        uint256 amount,
        address source
    ) external returns (uint256, uint256) {
        return super._withdrawToShares(poolId, amount, source);
    }
    // ------------------------- //
}
