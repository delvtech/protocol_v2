// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "contracts/ForwarderFactory.sol";

import "contracts/CompoundV3Term.sol";

import "contracts/mocks/MockERC20Permit.sol";
import "contracts/mocks/MockCompoundV3.sol";

import "@compoundV3/contracts/test/SimplePriceFeed.sol";
import "@compoundV3/contracts/CometConfiguration.sol";

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract CompoundV3TermTest is Test {
    ForwarderFactory public forwaderFactory;
    CompoundV3Term public term;

    User public user;
    MockCompoundV3 public compoundV3;

    MockERC20Permit public USDC;
    SimplePriceFeed public priceFeed_USDC;

    MockERC20Permit public WETH;
    SimplePriceFeed public priceFeed_WETH;

    function setUp() public {
        forwaderFactory = new ForwarderFactory();
        user = new User();

        USDC = new MockERC20Permit("USDC Coin", "USDC", 6);
        priceFeed_USDC = new SimplePriceFeed(1e6, 6);

        WETH = new MockERC20Permit("Wrapped Ether", "WETH", 18);
        priceFeed_WETH = new SimplePriceFeed(2000e18, 18);

        CometConfiguration.AssetConfig[] memory assetConfigs;
        assetConfigs[0] = CometConfiguration.AssetConfig({
            asset: address(WETH),
            priceFeed: address(priceFeed_WETH),
            decimals: 18,
            borrowCollateralFactor: 820000000000000000, // 0.82
            liquidateCollateralFactor: 850000000000000000, // 0.85
            liquidationFactor: 930000000000000000, // 0.93
            supplyCap: 1000000000000000000000000 // 1M
        });

        compoundV3 = new MockCompoundV3(address(USDC), address(priceFeed_WETH), assetConfigs);

        // term = new CompoundV3Term(
        //     ff.ERC20LINK_HASH(),
        //     address(ff),
        //     token,
        //     address(user)
        // );
    }

}
