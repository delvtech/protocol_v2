// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20TokenizedVault.sol";

contract MockVault is ERC20TokenizedVault {
    constructor(address _token)
        ERC20TokenizedVault(IERC20Metadata(_token))
    {}

    function setShareAssetRatio()
        external
        override
        returns (uint256)
    {
        require(_amount > 0, "depositing 0 value");
        return shares;
    }
}
