// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20TokenizedVault.sol";
import "./MockERC20.sol";

contract MockERC4626 is ERC20TokenizedVault {
    constructor(uint8 _decimals)
        ERC20TokenizedVault(new MockERC20(_decimals))
        ERC20("MockAssetToken share", "xMAT")
    {}

    // function maxDeposit(address) public view override returns (uint256) {
    //     return type(uint256).max;
    // }

    function issueShares(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function destroyShares(address account, uint256 amount) public {
        _burn(account, amount);
    }

    /// @notice Increments amount of deposited assets while shares remain
    /// constant
    // function incrementAssetAmount(uint256 _amount) public {
    //     burn(deposit(_amount, address(this)));
    // }

    // function decrementAssetAmount(uint256 _amount) public {
    //     withdraw(_amount, address(this), msg.sender);
    // }

    // function incrementShareAmount()
    // function decrementShareAmount()
}
