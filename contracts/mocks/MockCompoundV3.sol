// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.15;

import "@compoundV3/contracts/Comet.sol";

contract MockCompoundV3 is Comet {
    address _auth = address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84); // foundry test deployer

    constructor(
        address _baseToken,
        address _baseTokenPriceFeed,
        AssetConfig[] memory _assetConfigs
    )
        /// https://github.com/compound-finance/comet/blob/main/deployments/kovan/configuration.json
        Comet(
            Configuration({
                governor: _auth,
                pauseGuardian: _auth,
                baseToken: _baseToken,
                baseTokenPriceFeed: _baseTokenPriceFeed,
                extensionDelegate: address(0x0),
                supplyKink: 800000000000000000, // 0.8
                supplyPerYearInterestRateSlopeLow: 32500000000000000, // 0.0325
                supplyPerYearInterestRateSlopeHigh: 400000000000000000, // 0.4
                supplyPerYearInterestRateBase: 0,
                borrowKink: 800000000000000000, // 0.8
                borrowPerYearInterestRateSlopeLow: 35000000000000000, // 0.035
                borrowPerYearInterestRateSlopeHigh: 250000000000000000, // 0.25
                borrowPerYearInterestRateBase: 15000000000000000,
                storeFrontPriceFactor: 500000000000000000, // 0.5
                trackingIndexScale: 1000000000000000, //
                baseTrackingSupplySpeed: 11574074074,
                baseTrackingBorrowSpeed: 1145833333333,
                baseMinForRewards: 1000000000000, // 100k USDC
                baseBorrowMin: 1000000000, // 1000 USDC
                targetReserves: 5000000000000, // 500K USDC
                assetConfigs: _assetConfigs
            })
        )
    {}
}
