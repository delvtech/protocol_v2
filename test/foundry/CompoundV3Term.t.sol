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
    function create(Vm vm)
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
                // supplyPerYearInterestRateSlopeLow: 0.1e18,
                // supplyPerYearInterestRateSlopeHigh: 0.75e18,
                // supplyPerYearInterestRateBase: 0,
                // borrowKink: 0.8e18,
                // borrowPerYearInterestRateSlopeLow: 0.01e18,
                // borrowPerYearInterestRateSlopeHigh: 0.5e18,
                // borrowPerYearInterestRateBase: 0.4e18,
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

        // Move forward in time for yield to accrue in Compound
        vm.warp(block.timestamp + (365 * 24 * 60 * 60));
    }

    function calcSupplyApy(Comet _compound) public view returns (uint256 apy) {
        uint256 utilization = _compound.getUtilization();
        uint256 supplyRate = _compound.getSupplyRate(utilization);
        uint256 trackingIndexScale = _compound.trackingIndexScale();
        apy =
            ((supplyRate * trackingIndexScale) / 1e18) *
            (365 * 24 * 60 * 60) *
            1e5;
    }

    function sumPrincipalAndInterest(uint256 principal, uint256 APY)
        public
        pure
        returns (uint256)
    {
        return principal + ((principal * APY) / (1e18 * 100));
    }
}

contract CompoundV3TermTest is Test {
    CompoundV3Term public term;
    Comet public compound;

    MockERC20Permit public USDC;
    MockERC20Permit public WETH;

    address public user = vm.addr(0xFEED_DEAD_BEEF);

    uint256 public constant YEAR = (365 * 24 * 60 * 60);

    uint256 public TERM_START;
    uint256 public TERM_END;

    uint256[] public assetIds;
    uint256[] public assetAmounts;

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

        // Define the start and end dates for the term
        TERM_START = block.timestamp;
        TERM_END = TERM_START + YEAR;

        // mint the user capital
        vm.deal(user, 100 ether);
        USDC.mint(user, 1000000e6);
        vm.startPrank(user);
        USDC.approve(address(term), type(uint256).max);
        vm.stopPrank();

        // We want to emulate a live scenario so creating a scenario with a
        // large deposits in both a locked and unlocked position
        USDC.approve(address(term), type(uint256).max);
        USDC.mint(address(this), 2000000e6);

        term.lock(
            assetIds,
            assetAmounts,
            1000000e6,
            false,
            address(this),
            address(this),
            TERM_START,
            TERM_END
        );
        term.depositUnlocked(1000000e6, 0, 0, address(this));

        // Move halfway through the term so underlying and yieldShares are not 1:1
        vm.warp(block.timestamp + YEAR / 2);
    }

    function test__initialState() public {
        (
            uint256 underlyingReserve,
            uint256 yieldShareReserve,
            uint256 yieldShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = term.reserveDetails();

        uint256 yieldSharesIssued = term.yieldSharesIssued();

        // Roughly scaled 18 decimal representation of APY given current
        // per second supply rate
        uint256 estimatedSupplyAPY = CompoundV3TermHelper.calcSupplyApy(
            compound
        );

        // Divide by 2 to get 6 month rate
        uint256 estimated6MonthSupplyAPY = estimatedSupplyAPY / 2;

        uint256 estimatedYieldShareReserveValue = CompoundV3TermHelper
            .sumPrincipalAndInterest(
                yieldShareReserve,
                estimated6MonthSupplyAPY
            );

        uint256 estimatedYieldSharesIssuedValue = CompoundV3TermHelper
            .sumPrincipalAndInterest(
                yieldSharesIssued,
                estimated6MonthSupplyAPY
            );

        assertEq(underlyingReserve, 50000e6);
        assertEq(yieldShareReserve, 950000e6);
        assertEq(yieldSharesIssued, 1950000e6);
        assertApproxEqAbs(estimatedSupplyAPY, 2.5e18, 1e16);
        assertApproxEqAbs(
            estimatedYieldShareReserveValue,
            yieldShareReserveAsUnderlying,
            5e4
        );
        assertEq(
            impliedUnderlyingReserve,
            underlyingReserve + yieldShareReserveAsUnderlying
        );
        assertApproxEqAbs(
            estimatedYieldSharesIssuedValue,
            accruedUnderlying,
            5e4
        );
    }

    function test__depositLocked() public {
        uint256 input = 10000e6;
        uint256 inputAsShares = term.underlyingAsYieldShares(input);

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();

        uint256 prevYieldSharesIssued = term.yieldSharesIssued();

        vm.startPrank(user);
        term.lock(
            assetIds,
            assetAmounts,
            input,
            false,
            address(this),
            address(this),
            TERM_START,
            TERM_END
        );
        vm.stopPrank();

        (
            uint256 underlyingReserve,
            uint256 yieldShareReserve,
            uint256 yieldShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = term.reserveDetails();

        uint256 yieldSharesIssued = term.yieldSharesIssued();

        assertEq(underlyingReserve, prevUnderlyingReserve);
        assertEq(yieldShareReserve, prevYieldShareReserve);
        assertEq(yieldSharesIssued, prevYieldSharesIssued + inputAsShares);
        assertEq(
            prevYieldShareReserveAsUnderlying,
            yieldShareReserveAsUnderlying
        );
        assertEq(prevImpliedUnderlyingReserve, impliedUnderlyingReserve);
        assertApproxEqAbs(prevAccruedUnderlying + input, accruedUnderlying, 1);
    }

    function test__depositUnlocked__below_max_reserve() public {
        uint256 input = 10000e6;

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();

        uint256 prevYieldSharesIssued = term.yieldSharesIssued();

        vm.startPrank(user);
        term.depositUnlocked(input, 0, 0, user);
        vm.stopPrank();

        (
            uint256 underlyingReserve,
            uint256 yieldShareReserve,
            uint256 yieldShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = term.reserveDetails();

        uint256 yieldSharesIssued = term.yieldSharesIssued();

        assertEq(underlyingReserve, prevUnderlyingReserve + input);
        assertEq(yieldShareReserve, prevYieldShareReserve);
        assertEq(yieldSharesIssued, prevYieldSharesIssued);
        assertEq(
            yieldShareReserveAsUnderlying,
            prevYieldShareReserveAsUnderlying
        );
        assertEq(
            impliedUnderlyingReserve,
            prevImpliedUnderlyingReserve + input
        );
        assertEq(accruedUnderlying, prevAccruedUnderlying);
    }

    function test__depositUnlocked__above_max_reserve() public {
        uint256 input = 200000e6;
        uint256 inputInvested = 150000e6;

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();

        uint256 inputInvestedAsShares = term.underlyingAsYieldShares(
            inputInvested + prevUnderlyingReserve
        );

        uint256 prevYieldSharesIssued = term.yieldSharesIssued();

        vm.startPrank(user);
        term.depositUnlocked(input, 0, 0, user);
        vm.stopPrank();

        (
            uint256 underlyingReserve,
            uint256 yieldShareReserve,
            uint256 yieldShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = term.reserveDetails();

        uint256 yieldSharesIssued = term.yieldSharesIssued();

        assertEq(underlyingReserve, 50000e6);
        assertEq(
            yieldShareReserve,
            prevYieldShareReserve + inputInvestedAsShares
        );
        assertEq(
            yieldSharesIssued,
            prevYieldSharesIssued + inputInvestedAsShares
        );
        assertApproxEqAbs(
            yieldShareReserveAsUnderlying,
            prevYieldShareReserveAsUnderlying +
                inputInvested +
                prevUnderlyingReserve,
            1
        );
        assertApproxEqAbs(
            impliedUnderlyingReserve,
            prevImpliedUnderlyingReserve + input,
            1
        );
        assertApproxEqAbs(accruedUnderlying, prevAccruedUnderlying + input, 1);
    }

    function test__withdrawLocked() public {
        uint256 inputDeposited = 1000000e6;

        vm.startPrank(user);
        term.lock(
            assetIds,
            assetAmounts,
            inputDeposited,
            false,
            address(this),
            address(this),
            TERM_START,
            TERM_END
        );
        vm.stopPrank();

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();

        uint256 prevYieldSharesIssued = term.yieldSharesIssued();

        uint256 sharesToRedeem = 10000e6;
        uint256 estimatedWithdrawnUnderlying = term.yieldSharesAsUnderlying(
            sharesToRedeem
        );

        vm.startPrank(user);
        assetIds[0] = TERM_END;
        assetAmounts[0] = sharesToRedeem;
        term.unlock(user, assetIds, assetAmounts);
        vm.stopPrank();

        (
            uint256 underlyingReserve,
            uint256 yieldShareReserve,
            uint256 yieldShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = term.reserveDetails();

        uint256 yieldSharesIssued = term.yieldSharesIssued();

        assertEq(underlyingReserve, prevUnderlyingReserve);
        assertEq(yieldShareReserve, prevYieldShareReserve);
        assertEq(yieldSharesIssued, prevYieldSharesIssued - sharesToRedeem);
        assertEq(
            yieldShareReserveAsUnderlying,
            prevYieldShareReserveAsUnderlying
        );
        assertEq(impliedUnderlyingReserve, prevImpliedUnderlyingReserve);
        assertApproxEqAbs(
            accruedUnderlying,
            prevAccruedUnderlying - estimatedWithdrawnUnderlying,
            1
        );
    }

    function test__withdrawUnlocked() public {}

    function test__convertLocked() public {}

    function test__convertUnlocked() public {}

    function test__underlyingLocked() public {}

    function test__underlyingUnlocked() public {}
}
