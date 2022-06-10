// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20TokenizedVault.sol";
import "../interfaces/IYieldAdapter.sol";

contract ERC4626YieldAdapter is IYieldAdapter {
    ERC20TokenizedVault public immutable vault;

    constructor(address _vault) {
        vault = ERC20TokenizedVault(_vault);
    }

    function deposit() external returns (uint256, uint256) {
        return (0, 0);
    }

    function withdraw(
        uint256 _shares,
        address _destination,
        uint256 _minUnderlying
    ) external returns (uint256) {
        return 0;
    }

    function underlying(uint256 _amount) external view returns (uint256) {
        return 0;
    }
}
