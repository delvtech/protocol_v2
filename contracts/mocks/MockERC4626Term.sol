// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../ERC4626Term.sol";

contract MockERC4626Term is ERC4626Term {
    constructor(IERC4626 _vault, uint256 _maxReserve)
        ERC4626Term(_vault, bytes32(0x0), address(0x0), _maxReserve)
    {}

    function underlying(uint256 _shares, ShareState _state)
        public
        view
        returns (uint256)
    {
        return _underlying(_shares, _state);
    }
}
