// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "contracts/ForwarderFactory.sol";

import "contracts/CompoundV3Term.sol";

import "contracts/mocks/MockERC20Permit.sol";

import "@compoundV3/contracts/Comet.sol";
import "@compoundV3/contracts/test/SimplePriceFeed.sol";
import "@compoundV3/contracts/CometConfiguration.sol";
import "@compoundV3/contracts/CometStorage.sol";

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

contract CompoundV3TermTest is Test {
    CompoundV3Term public term;

    MockCompoundV3 public compound;

    MockERC20Permit public USDC;

    MockERC20Permit public WETH;
    SimplePriceFeed public priceFeed_WETH;

    address public Alice = vm.addr(0xA11CE);
    address public Bob = vm.addr(0xB0B);
    address public Carol = vm.addr(0xCA701);

    uint256 public amountCollateral;
    uint256 public amountDebt;
    uint256 public amountSupply;

    uint256 public constant MAX_RESERVE = 50000e18;
    uint256 public constant YEAR = (365 * 24 * 60 * 60);

    uint256 public TERM_START;
    uint256 public TERM_END;

    function labels() public {
        vm.label(Alice, "Alice");
        vm.label(Bob, "Bob");
        vm.label(Carol, "Carol");
        vm.label(address(compound), "Compound");
        vm.label(address(USDC), "USDC");
        vm.label(address(WETH), "WETH");
    }

    function setUp() public {
        ForwarderFactory forwarderFactory = new ForwarderFactory();

        USDC = new MockERC20Permit("USDC Coin", "USDC", 6);
        WETH = new MockERC20Permit("Wrapped Ether", "WETH", 18);

        SimplePriceFeed priceFeed_USDC = new SimplePriceFeed(1e8, 8);
        SimplePriceFeed priceFeed_WETH = new SimplePriceFeed(2000e8, 8);

        CometConfiguration.AssetConfig[]
            memory assetConfigs = new CometConfiguration.AssetConfig[](1);
        assetConfigs[0] = CometConfiguration.AssetConfig({
            asset: address(WETH),
            priceFeed: address(priceFeed_WETH),
            decimals: 18,
            borrowCollateralFactor: 0.8e18,
            liquidateCollateralFactor: 0.85e18,
            liquidationFactor: 0.93e18,
            supplyCap: 1000000e18
        });

        compound = new MockCompoundV3(
            address(USDC),
            address(priceFeed_USDC),
            assetConfigs
        );

        term = new CompoundV3Term(
            address(compound),
            forwarderFactory.ERC20LINK_HASH(),
            address(forwarderFactory),
            MAX_RESERVE,
            address(this)
        );

        compound.initializeStorage();

        amountSupply = 10000000e6;
        amountDebt = 8000000e6;
        amountCollateral = 10000e18;

        vm.deal(Alice, 100 ether);
        vm.deal(Bob, 100 ether);
        vm.deal(Carol, 100 ether);

        USDC.mint(Alice, amountSupply);
        WETH.mint(Bob, amountCollateral);
        USDC.mint(Bob, 1_000_000e6);
        USDC.mint(Carol, 100000e6);

        labels();

        vm.startPrank(Alice);
        USDC.approve(address(compound), type(uint256).max);
        WETH.approve(address(compound), type(uint256).max);
        compound.supply(address(USDC), amountSupply);
        vm.stopPrank();

        vm.startPrank(Bob);
        USDC.approve(address(term), type(uint256).max);
        WETH.approve(address(compound), type(uint256).max);
        compound.supply(address(WETH), amountCollateral);
        compound.withdraw(address(USDC), amountDebt);
        vm.stopPrank();

        // Advance a year in time to accrue some yield
        vm.warp(block.timestamp + YEAR);

        vm.startPrank(Carol);
        USDC.approve(address(term), type(uint256).max);
        vm.stopPrank();

        TERM_START = block.timestamp;
        TERM_END = TERM_START + YEAR;

        vm.startPrank(Bob);
        uint256[] memory assetIds;
        uint256[] memory assetAmounts;

        term.lock(
            assetIds,
            assetAmounts,
            10_000e6,
            false,
            Bob,
            Bob,
            TERM_START,
            TERM_END
        );
        vm.stopPrank();

        // Move halfway through the term
        vm.warp(block.timestamp + YEAR / 2);
    }

    // validate that compound supply and withdrawals work
    function test__compoundYieldAccrual() public {
        uint256 preTotalSupply = compound.totalSupply();
        uint256 preTotalBorrow = compound.totalBorrow();

        assertEq(preTotalSupply, amountSupply);
        assertEq(preTotalBorrow, amountDebt);

        uint256 utilization = compound.getUtilization();
        uint256 borrowRate = compound.getBorrowRate(utilization);
        uint256 supplyRate = compound.getSupplyRate(utilization);

        vm.warp(block.timestamp + YEAR);

        uint256 postTotalSupply = compound.totalSupply();
        uint256 postTotalBorrow = compound.totalBorrow();

        assertEq(postTotalSupply >= preTotalSupply, true);
        assertEq(postTotalBorrow >= preTotalBorrow, true);

        uint256 supplyInterest = postTotalSupply - preTotalSupply;
        uint256 borrowInterest = postTotalBorrow - preTotalBorrow;

        assertEq(borrowInterest >= supplyInterest, true);
    }

    function test__termDeployment() public {
        assertEq(address(term.yieldSource()) == address(compound), true);
        assertEq(term.underlyingReserve(), 0);
        assertEq(term.yieldSharesIssued(), 0);
        assertEq(term.yieldShareReserve(), 0);
        assertEq(term.targetReserve(), 25000e18);
        assertEq(term.maxReserve(), 50000e18);
        assertEq(USDC.balanceOf(address(term)), 0);
        assertEq(compound.balanceOf(address(term)), 0);
        assertEq(term.totalSupply(term.UNLOCKED_YT_ID()), 0);
    }

    /// Should lock amount of underlying directly in the protocol
    /// and issue shares according to the current (inferred) yield share price
    function test__depositLocked() public {
        uint256 usdcCompoundBalance = USDC.balanceOf(address(compound));

        // console2.log(term.yieldSharesAsUnderlying(10000e6));
        // console2.log(term.underlyingAsYieldShares(10000e6));
        // console2.log(term.yieldSharesIssued());

        vm.startPrank(Carol);
        uint256[] memory assetIds;
        uint256[] memory assetAmounts;
        term.lock(
            assetIds,
            assetAmounts,
            10000e6,
            false,
            Carol,
            Carol,
            TERM_START,
            TERM_END
        );
        vm.stopPrank();

        // console2.log(term.yieldSharesAsUnderlying(10000e6));
        // console2.log(term.underlyingAsYieldShares(10000e6));
        // console2.log(term.yieldSharesIssued());

        vm.startPrank(Carol);
        term.lock(
            assetIds,
            assetAmounts,
            10000e6,
            false,
            Carol,
            Carol,
            TERM_START,
            TERM_END
        );
        vm.stopPrank();

        // console2.log(term.yieldSharesAsUnderlying(10000e6));
        // console2.log(term.underlyingAsYieldShares(10000e6));
        // console2.log(term.yieldSharesIssued());

        // usdcCompoundBalance =
        //     USDC.balanceOf(address(compound)) -
        //     usdcCompoundBalance;

        // assertEq(shares, 10000e6);
        // assertEq(underlying, 10000e6);
        // assertEq(usdcCompoundBalance, 10000e6);
        // assertEq(compound.balanceOf(address(term)), 10000e6);
    }
}
