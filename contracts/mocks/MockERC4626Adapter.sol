// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.12;

import "../adapters/ERC4626Adapter.sol";

contract MockERC4626Adapter is ERC4626Adapter {
    constructor(IERC4626 _vault, uint256 _reserveLimit)
        ERC4626Adapter(_vault, _reserveLimit)
    {}

    function deposit(ShareState _state)
        public
        returns (uint256 amountUnderlying, uint256 shares)
    {
        return _deposit(_state);
    }

    function withdraw(
        uint256 _amountShares,
        address _dest,
        ShareState _state
    ) public returns (uint256) {
        return _withdraw(_amountShares, _dest, _state);
    }

    function convert(ShareState _state, uint256 _amount)
        public
        returns (uint256)
    {
        return _convert(_state, _amount);
    }

    function underlying(uint256 _amount, ShareState _state)
        public
        view
        returns (uint256)
    {
        return _underlying(_amount, _state);
    }
}
