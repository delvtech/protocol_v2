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

library CompoundV3TermHelper {
    // Deploys both Compound and CompoundV3Term contracts and sets up an
    // emulated live scenario
    function createCompound(Vm vm)
        public
        returns (
            Comet compound,
            CompoundV3Term term,
            MockERC20Permit USDC,
            MockERC20Permit WETH
        )
    {
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

        CometConfiguration.Configuration memory cometConfig = CometConfiguration
            .Configuration({
                governor: msg.sender,
                pauseGuardian: msg.sender,
                baseToken: address(USDC),
                baseTokenPriceFeed: address(priceFeed_USDC),
                extensionDelegate: address(0x0),
                supplyKink: 0.8e18, // 0.8
                supplyPerYearInterestRateSlopeLow: 0.0325e18,
                supplyPerYearInterestRateSlopeHigh: 0.4e18,
                supplyPerYearInterestRateBase: 0,
                borrowKink: 0.8e18,
                borrowPerYearInterestRateSlopeLow: 0.035e18,
                borrowPerYearInterestRateSlopeHigh: 0.25e18,
                borrowPerYearInterestRateBase: 0.15e18,
                storeFrontPriceFactor: 0.5e18,
                trackingIndexScale: 1e15,
                baseTrackingSupplySpeed: 11574074074074073,
                baseTrackingBorrowSpeed: 11458333333333333,
                baseMinForRewards: 100000e6,
                baseBorrowMin: 1000e6,
                targetReserves: 5000000e6,
                assetConfigs: assetConfigs
            });

        compound = new Comet(cometConfig);

        ForwarderFactory forwarderFactory = new ForwarderFactory();

        term = new CompoundV3Term(
            address(compound),
            forwarderFactory.ERC20LINK_HASH(),
            address(forwarderFactory),
            100_000e6,
            address(this)
        );

        compound.initializeStorage();

        address Alice = vm.addr(0xA11CE);
        address Bob = vm.addr(0xB0B);

        vm.deal(Alice, 100 ether);
        vm.deal(Bob, 100 ether);

        USDC.mint(Alice, 10000000e6);
        USDC.mint(Bob, 1000000e6);
        WETH.mint(Bob, 10000e18);

        vm.startPrank(Alice);
        USDC.approve(address(compound), type(uint256).max);
        WETH.approve(address(compound), type(uint256).max);
        compound.supply(address(USDC), 10000000e6);
        vm.stopPrank();

        vm.startPrank(Bob);
        USDC.approve(address(term), type(uint256).max);
        WETH.approve(address(compound), type(uint256).max);
        compound.supply(address(WETH), 10000e18);
        compound.withdraw(address(USDC), 8000000e6);
        vm.stopPrank();
    }
}

contract CompoundV3TermTest is Test {
    CompoundV3Term public lockedTerm;

    Comet public compound;

    MockERC20Permit public USDC;
    MockERC20Permit public WETH;

    address public user = vm.addr(0xFEED_DEAD_BEEF);

    uint256 public constant YEAR = (365 * 24 * 60 * 60);

    uint256 public TERM_START;
    uint256 public TERM_END;

    function labels() public {
        vm.label(user, "User");
        vm.label(address(compound), "Compound");
        vm.label(address(term), "Term");
        vm.label(address(USDC), "USDC");
        vm.label(address(WETH), "WETH");
    }

    function setUp() public {
        (compound, term, USDC, WETH) = CompoundV3TermHelper.create(vm);

        labels();

        vm.warp(block.timestamp + YEAR);

        USDC.mint(user, 1_000_000e6);
        USDC.mint(address(this), 1_000_000e6);
        vm.deal(user, 100 ether);

        vm.startPrank(user);
        USDC.approve(address(term), type(uint256).max);
        vm.stopPrank();

        TERM_START = block.timestamp;
        TERM_END = TERM_START + YEAR;

        // Move halfway through the term so underlying and yieldShares are not 1:1
        vm.warp(block.timestamp + YEAR / 2);
    }

    // validate that compound supply and withdrawals work
    // function test__compoundYieldAccrual() public {
    //     uint256 preTotalSupply = compound.totalSupply();
    //     uint256 preTotalBorrow = compound.totalBorrow();

    //     assertEq(preTotalSupply, amountSupply);
    //     assertEq(preTotalBorrow, amountDebt);

    //     uint256 utilization = compound.getUtilization();
    //     uint256 borrowRate = compound.getBorrowRate(utilization);
    //     uint256 supplyRate = compound.getSupplyRate(utilization);

    //     vm.warp(block.timestamp + YEAR);

    //     uint256 postTotalSupply = compound.totalSupply();
    //     uint256 postTotalBorrow = compound.totalBorrow();

    //     assertEq(postTotalSupply >= preTotalSupply, true);
    //     assertEq(postTotalBorrow >= preTotalBorrow, true);

    //     uint256 supplyInterest = postTotalSupply - preTotalSupply;
    //     uint256 borrowInterest = postTotalBorrow - preTotalBorrow;

    //     assertEq(borrowInterest >= supplyInterest, true);
    // }

    // function test__termDeployment() public {
    //     assertEq(address(term.yieldSource()) == address(compound), true);
    //     assertEq(term.underlyingReserve(), 0);
    //     assertEq(term.yieldSharesIssued(), 0);
    //     assertEq(term.yieldShareReserve(), 0);
    //     assertEq(term.targetReserve(), 25000e18);
    //     assertEq(term.maxReserve(), 50000e18);
    //     assertEq(USDC.balanceOf(address(term)), 0);
    //     assertEq(compound.balanceOf(address(term)), 0);
    //     assertEq(term.totalSupply(term.UNLOCKED_YT_ID()), 0);
    // }

    /// Should lock amount of underlying directly in the protocol
    /// and issue shares according to the current (inferred) yield share price
    function test__depositLocked() public {
        uint256 usdcCompoundBalance = USDC.balanceOf(address(compound));

        // console2.log(term.yieldSharesAsUnderlying(10000e6));
        // console2.log(term.underlyingAsYieldShares(10000e6));
        // console2.log(term.yieldSharesIssued());

        vm.startPrank(user);
        uint256[] memory assetIds;
        uint256[] memory assetAmounts;
        term.lock(
            assetIds,
            assetAmounts,
            10000e6,
            false,
            user,
            user,
            TERM_START,
            TERM_END
        );
        vm.stopPrank();

        // console2.log(term.yieldSharesAsUnderlying(10000e6));
        // console2.log(term.underlyingAsYieldShares(10000e6));
        // console2.log(term.yieldSharesIssued());

        vm.startPrank(user);
        term.lock(
            assetIds,
            assetAmounts,
            10000e6,
            false,
            user,
            user,
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
