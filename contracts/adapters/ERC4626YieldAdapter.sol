// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "./YieldAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20TokenizedVault.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract ERC4626YieldAdapter is YieldAdapter {
    constructor(address _term, address _vault)
        YieldAdapter(_term, _vault, _vault, ERC20TokenizedVault(_vault).asset())
    {}

    function deposit() external override returns (uint256, uint256) {
        return (0, 0);
    }

    function withdraw(
        uint256 _shares,
        address _destination,
        uint256 _minUnderlying
    ) external override returns (uint256) {
        return 0;
    }

    function pricePerShare(uint256 _amount)
        external
        override
        returns (uint256)
    {
        return uint256(0);
    }
}
