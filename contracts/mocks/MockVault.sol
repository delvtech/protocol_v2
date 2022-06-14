// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20TokenizedVault.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "./MockAsset.sol";

contract MockVault is ERC20TokenizedVault {
    address public owner;

    constructor(address _receiver)
        ERC20("MockShareToken", "xMAT")
        ERC20TokenizedVault(new MockAsset(1_000_000 ether, _receiver))
    {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Sender not owner");
        _;
    }


    // function mintAssetToSender

    // function issueDivididend

}
