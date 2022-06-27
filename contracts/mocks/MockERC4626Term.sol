// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../ERC4626Term.sol";
import "../interfaces/IERC20Mint.sol";

contract MockERC4626Term is ERC4626Term {
    constructor(IERC4626 _vault, uint256 _maxReserve)
        ERC4626Term(_vault, bytes32(0x0), address(0x0), _maxReserve)
    {}

    event MockDeposit(
        address indexed depositor,
        uint256 underlyingDeposited,
        uint256 shares
    );

    function deposit(ShareState _state, uint256 _amountUnderlying)
        public
        returns (uint256, uint256)
    {
        IERC20(vault.asset()).transferFrom(
            msg.sender,
            address(this),
            _amountUnderlying
        );
        (uint256 underlyingDeposited, uint256 shares) = _deposit(_state);
        emit MockDeposit(msg.sender, underlyingDeposited, shares);
    }

    function withdraw(
        uint256 _shares,
        address _dest,
        ShareState _state
    ) public returns (uint256) {
        return _withdraw(_shares, _dest, _state);
    }

    function convert(ShareState _state, uint256 _shares)
        public
        returns (uint256)
    {
        return _convert(_state, _shares);
    }

    function underlying(uint256 _shares, ShareState _state)
        public
        view
        returns (uint256)
    {
        return _underlying(_shares, _state);
    }

    function setTotalSupply(uint256 _supply) external {
        totalSupply[UNLOCKED_YT_ID] = _supply;
    }
}
