// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";

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

    function principalTokensAsShares(
        CompoundV3Term term,
        uint256 expiry,
        uint256 amount
    ) public view returns (uint256 shares) {
        uint256 termShares = term.sharesPerExpiry(expiry);
        uint256 ptTotalSupply = term.totalSupply(expiry);

        uint256 termSharesAsUnderlying = term.yieldSharesAsUnderlying(
            termShares
        );
        uint256 termUnderlyingInterest = termSharesAsUnderlying - ptTotalSupply;

        uint256 one = term.one();
        uint256 underlyingPricePerShare = term.yieldSharesAsUnderlying(one);

        uint256 termSharesForInterest = (termUnderlyingInterest * one) /
            underlyingPricePerShare;

        uint256 termSharesForPts = termShares - termSharesForInterest;
        shares = (amount * termSharesForPts) / ptTotalSupply;
    }

    function underlyingAsUnlockedShares(CompoundV3Term term, uint256 underlying)
        public
        view
        returns (uint256 shares)
    {
        (, , , uint256 impliedUnderlyingReserve, ) = term.reserveDetails();
        shares =
            (underlying * term.totalSupply(term.UNLOCKED_YT_ID())) /
            impliedUnderlyingReserve;
    }

    function unlockedSharesAsUnderlying(CompoundV3Term term, uint256 shares)
        public
        view
        returns (uint256 underlying)
    {
        (, , , uint256 impliedUnderlyingReserve, ) = term.reserveDetails();
        underlying =
            (shares * impliedUnderlyingReserve) /
            term.totalSupply(term.UNLOCKED_YT_ID());
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

    uint256 public UNLOCKED_YT_ID;

    uint256 public PT_ID;
    uint256 public YT_ID;

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

        uint256[] memory assetIds;
        uint256[] memory assetAmounts;

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

        UNLOCKED_YT_ID = term.UNLOCKED_YT_ID();
        PT_ID = TERM_END;
        YT_ID = (1 << 255) + (TERM_START << 128) + TERM_END;

        // Move halfway through the term so underlying and yieldShares are not 1:1
        vm.warp(block.timestamp + YEAR / 2);
    }

    function test__initialState() public {
        assertEq(
            block.timestamp,
            TERM_START + (YEAR / 2),
            "should be 6 months into term"
        );
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
        assertEq(term.balanceOf(PT_ID, address(this)), 1000000e6);
        assertEq(term.balanceOf(YT_ID, address(this)), 1000000e6);
        assertEq(term.balanceOf(UNLOCKED_YT_ID, address(this)), 1000000e6);
    }

    function test__depositLocked() public {
        uint256 underlying = 10000e6;
        uint256 underlyingAsYieldShares = term.underlyingAsYieldShares(
            underlying
        );

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();

        uint256 prevYieldSharesIssued = term.yieldSharesIssued();

        uint256[] memory assetIds;
        uint256[] memory assetAmounts;

        vm.startPrank(user);
        term.lock(
            assetIds,
            assetAmounts,
            underlying,
            false,
            user,
            user,
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

        assertEq(
            underlyingReserve,
            prevUnderlyingReserve,
            "underlyingReserve should be unchanged"
        );
        assertEq(
            yieldShareReserve,
            prevYieldShareReserve,
            "yieldShareReserve should be unchanged"
        );
        assertEq(
            yieldSharesIssued,
            prevYieldSharesIssued + underlyingAsYieldShares,
            "yieldSharesIssued should increase by yieldShare value of underlying"
        );
        assertEq(
            prevYieldShareReserveAsUnderlying,
            yieldShareReserveAsUnderlying,
            "yieldSharesReserveAsUnderlying should be unchanged"
        );
        assertEq(
            prevImpliedUnderlyingReserve,
            impliedUnderlyingReserve,
            "impliedUnderlyingReserve should be unchanged"
        );
        assertApproxEqAbs(
            prevAccruedUnderlying + underlying,
            accruedUnderlying,
            1,
            "accruedUnderlying should increase by amount of underlying"
        );
        assertEq(
            term.balanceOf(YT_ID, user),
            underlying,
            "should issue YT's to user proportional to amount of underlying"
        );
    }

    function test__depositUnlocked__below_max_reserve() public {
        uint256 underlying = 10000e6;
        uint256 underlyingAsUnlockedShares = CompoundV3TermHelper
            .underlyingAsUnlockedShares(term, underlying);

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();

        uint256 prevYieldSharesIssued = term.yieldSharesIssued();

        vm.startPrank(user);
        term.depositUnlocked(underlying, 0, 0, user);
        vm.stopPrank();

        (
            uint256 underlyingReserve,
            uint256 yieldShareReserve,
            uint256 yieldShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = term.reserveDetails();

        uint256 yieldSharesIssued = term.yieldSharesIssued();

        assertEq(
            underlyingReserve,
            prevUnderlyingReserve + underlying,
            "underlyingReserve should increase by amount of underlying"
        );
        assertEq(
            yieldShareReserve,
            prevYieldShareReserve,
            "yieldShareReserve should be unchanged"
        );
        assertEq(
            yieldSharesIssued,
            prevYieldSharesIssued,
            "yieldSharesIssued should be unchanged"
        );
        assertEq(
            yieldShareReserveAsUnderlying,
            prevYieldShareReserveAsUnderlying,
            "yieldShareReserveAsUnderlying should be unchanged"
        );
        assertEq(
            impliedUnderlyingReserve,
            prevImpliedUnderlyingReserve + underlying,
            "impliedUnderlyingReserve should increase by amount of underlying"
        );
        assertEq(
            accruedUnderlying,
            prevAccruedUnderlying,
            "accruedUnderlying should be unchanged"
        );
        assertEq(
            term.balanceOf(UNLOCKED_YT_ID, user),
            underlyingAsUnlockedShares,
            "should issue unlocked YTs to user proportional to unlock share value of underlying"
        );
    }

    function test__depositUnlocked__above_max_reserve() public {
        uint256 underlying = 200000e6;
        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();
        uint256 prevYieldSharesIssued = term.yieldSharesIssued();

        uint256 targetReserve = term.targetReserve();
        assertEq(targetReserve, 50000e6);
        assertEq(prevUnderlyingReserve, 50000e6);

        assertTrue(
            underlying + prevUnderlyingReserve > term.maxReserve(),
            "total amount of underlying existant in the contract should exceed the maxReserve"
        );

        uint256 underlyingInvested = underlying +
            prevUnderlyingReserve -
            targetReserve;
        uint256 underlyingInvestedAsUnlockedShares = CompoundV3TermHelper
            .underlyingAsUnlockedShares(term, underlyingInvested);
        uint256 underlyingInvestedAsYieldShares = term.underlyingAsYieldShares(
            underlyingInvested
        );

        vm.startPrank(user);
        term.depositUnlocked(underlying, 0, 0, user);
        vm.stopPrank();

        (
            uint256 underlyingReserve,
            uint256 yieldShareReserve,
            uint256 yieldShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = term.reserveDetails();

        uint256 yieldSharesIssued = term.yieldSharesIssued();

        assertEq(
            underlyingReserve,
            targetReserve,
            "underlyingReserve should be equal to the targetReserve"
        );
        assertEq(
            yieldShareReserve,
            prevYieldShareReserve + underlyingInvestedAsYieldShares,
            "yieldShareReserve should increase by yieldShare value of invested underlying"
        );
        assertEq(
            yieldSharesIssued,
            prevYieldSharesIssued + underlyingInvestedAsYieldShares,
            "yieldSharesIssued should increase by yieldShare value of invested underlying"
        );
        assertApproxEqAbs(
            yieldShareReserveAsUnderlying,
            prevYieldShareReserveAsUnderlying + underlyingInvested,
            1,
            "yieldShareReserveAsUnderlying should increase by amount of invested underlying"
        );
        assertApproxEqAbs(
            impliedUnderlyingReserve,
            prevImpliedUnderlyingReserve + underlyingInvested,
            1,
            "impliedUnderlyingReserve should increase by amount of invested underlying"
        );
        assertApproxEqAbs(
            accruedUnderlying,
            prevAccruedUnderlying + underlyingInvested,
            1,
            "accruedUnderlyingReserve should increase by amount of invested underlying"
        );
        assertEq(
            term.balanceOf(UNLOCKED_YT_ID, user),
            underlyingInvestedAsUnlockedShares,
            "should issue unlocked YTs to user proportional to unlock share value of underlying"
        );
    }

    function test__withdrawLocked() public {
        uint256 inputDeposited = 1000000e6;

        uint256[] memory assetIds;
        uint256[] memory assetAmounts;

        vm.startPrank(user);
        term.lock(
            assetIds,
            assetAmounts,
            inputDeposited,
            false,
            user,
            user,
            TERM_START,
            TERM_END
        );
        vm.stopPrank();

        // Go to 1 second after TERM_END
        vm.warp(block.timestamp + (YEAR / 2) + 1);
        assertEq(
            block.timestamp,
            TERM_END + 1,
            "should be 1 second after term end"
        );

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();

        uint256 prevYieldSharesIssued = term.yieldSharesIssued();
        uint256 prevPrincipalTokenBalance = term.balanceOf(PT_ID, user);
        uint256 prevYieldTokenBalance = term.balanceOf(YT_ID, user);

        uint256 pts = 10000e6;
        uint256 ptsAsShares = CompoundV3TermHelper.principalTokensAsShares(
            term,
            TERM_END,
            pts
        );
        uint256 ptsAsUnderlying = term.yieldSharesAsUnderlying(ptsAsShares);

        vm.startPrank(user);
        assetIds = new uint256[](1);
        assetAmounts = new uint256[](1);
        assetIds[0] = TERM_END;
        assetAmounts[0] = pts;
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

        assertEq(
            underlyingReserve,
            prevUnderlyingReserve,
            "underlyingReserve should be unchanged"
        );
        assertEq(
            yieldShareReserve,
            prevYieldShareReserve,
            "yieldShareReserve should be unchanged"
        );
        assertEq(
            yieldSharesIssued,
            prevYieldSharesIssued - ptsAsShares,
            "yieldSharesIssued should decrease by the share value of withdrawn PTs"
        );
        assertEq(
            yieldShareReserveAsUnderlying,
            prevYieldShareReserveAsUnderlying,
            "yieldSharesReserveAsUnderlying should be unchanged"
        );
        assertEq(
            impliedUnderlyingReserve,
            prevImpliedUnderlyingReserve,
            "impliedUnderlyingReserve should be unchanged"
        );
        assertApproxEqAbs(
            accruedUnderlying,
            prevAccruedUnderlying - ptsAsUnderlying,
            1,
            "accruedUnderlying should decrease by the underlying value of withdrawn PTs"
        );
        assertEq(
            term.balanceOf(PT_ID, user),
            prevPrincipalTokenBalance - pts,
            "user principal token balance should decrease by amount of withdrawn PTs"
        );
        assertEq(
            term.balanceOf(YT_ID, user),
            prevYieldTokenBalance,
            "user yield token balance should be unchanged"
        );
    }

    function test__withdrawUnlocked__less_than_underlying_reserve() public {
        uint256 underlyingDeposited = 1000000e6;

        vm.startPrank(user);
        term.depositUnlocked(underlyingDeposited, 0, 0, user);
        vm.stopPrank();

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();

        uint256 prevYieldSharesIssued = term.yieldSharesIssued();

        uint256 prevYieldTokenBalance = term.balanceOf(UNLOCKED_YT_ID, user);
        uint256 prevUnderlyingBalance = USDC.balanceOf(user);

        uint256 unlockedYts = 10000e6;
        uint256 unlockedYtsAsUnderlying = CompoundV3TermHelper
            .unlockedSharesAsUnderlying(term, unlockedYts);

        assertTrue(unlockedYtsAsUnderlying <= prevUnderlyingReserve);

        uint256[] memory assetIds = new uint256[](1);
        uint256[] memory assetAmounts = new uint256[](1);

        assetIds[0] = UNLOCKED_YT_ID;
        assetAmounts[0] = unlockedYts;

        vm.startPrank(user);
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

        assertEq(
            underlyingReserve,
            prevUnderlyingReserve - unlockedYtsAsUnderlying,
            "underlyingReserve should decrease by underlying value of unlocked YTs"
        );
        assertEq(
            yieldShareReserve,
            prevYieldShareReserve,
            "yieldShareReserve should be unchanged"
        );
        assertEq(
            yieldSharesIssued,
            prevYieldSharesIssued,
            "yieldSharesIssued should be unchanged"
        );
        assertEq(
            yieldShareReserveAsUnderlying,
            prevYieldShareReserveAsUnderlying,
            "yieldShareReserveAsUnderlying should be unchanged"
        );
        assertEq(
            impliedUnderlyingReserve,
            prevImpliedUnderlyingReserve - unlockedYtsAsUnderlying,
            "impliedUnderlyingReserve should decrease by underlying value of unlocked YTs"
        );
        assertApproxEqAbs(
            accruedUnderlying,
            prevAccruedUnderlying,
            1,
            "accruedUnderlying should be unchanged"
        );
        assertEq(
            term.balanceOf(UNLOCKED_YT_ID, user),
            prevYieldTokenBalance - unlockedYts,
            "user unlocked yield token balance should decrease by amount of redeemed unlocked YTs"
        );
        assertEq(
            USDC.balanceOf(user),
            prevUnderlyingBalance + unlockedYtsAsUnderlying,
            "user underlying token balance should increase by underlying value of redeemed unlocked YTs"
        );
    }

    function test__withdrawUnlocked__greater_than_underlying_reserve() public {
        uint256 underlyingDeposited = 1000000e6;

        vm.startPrank(user);
        term.depositUnlocked(underlyingDeposited, 0, 0, user);
        vm.stopPrank();

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();

        uint256 prevYieldSharesIssued = term.yieldSharesIssued();

        uint256 prevYieldTokenBalance = term.balanceOf(UNLOCKED_YT_ID, user);
        uint256 prevUnderlyingBalance = USDC.balanceOf(user);

        uint256 unlockedYts = 100000e6;
        uint256 unlockedYtsAsUnderlying = CompoundV3TermHelper
            .unlockedSharesAsUnderlying(term, unlockedYts);
        uint256 unlockedYtsAsYieldShares = term.underlyingAsYieldShares(
            unlockedYtsAsUnderlying
        );

        uint256[] memory assetIds = new uint256[](1);
        uint256[] memory assetAmounts = new uint256[](1);

        assetIds[0] = UNLOCKED_YT_ID;
        assetAmounts[0] = unlockedYts;

        vm.startPrank(user);
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

        assertEq(
            underlyingReserve,
            prevUnderlyingReserve,
            "underlying reserve should be unchanged"
        );
        assertEq(
            yieldShareReserve,
            prevYieldShareReserve - unlockedYtsAsYieldShares,
            "yieldShareReserve should decrease by yieldShare value of unlocked YTs"
        );
        assertEq(
            yieldSharesIssued,
            prevYieldSharesIssued - unlockedYtsAsYieldShares,
            "yieldSharesIsued should decrease by yieldShare value of unlocked YTs"
        );
        assertEq(
            yieldShareReserveAsUnderlying,
            prevYieldShareReserveAsUnderlying - unlockedYtsAsUnderlying,
            "yieldShareReserveAsUnderlying should decrease by underlying value of unlocked YTs"
        );
        assertEq(
            impliedUnderlyingReserve,
            prevImpliedUnderlyingReserve - unlockedYtsAsUnderlying,
            "impliedUnderlyingReserve should decrease by underlying value of unlocked YTs"
        );
        assertApproxEqAbs(
            accruedUnderlying,
            prevAccruedUnderlying - unlockedYtsAsUnderlying,
            1,
            "accruedUnderlying should decrease by underlying value of unlocked YTs"
        );
        assertEq(
            term.balanceOf(UNLOCKED_YT_ID, user),
            prevYieldTokenBalance - unlockedYts,
            "user unlocked yield token balance should decrease by amount of redeemed unlocked YTs"
        );
        assertEq(
            USDC.balanceOf(user),
            prevUnderlyingBalance + unlockedYtsAsUnderlying,
            "user underlying token balance should increase by underlying value of redeemed unlocked YTs"
        );
    }

    function test__convertLocked() public {
        uint256 underlying = 1000000e6;

        uint256[] memory assetIds;
        uint256[] memory assetAmounts;

        vm.startPrank(user);
        term.lock(
            assetIds,
            assetAmounts,
            underlying,
            false,
            user,
            user,
            TERM_START,
            TERM_END
        );
        vm.stopPrank();

        vm.warp(block.timestamp + YEAR + 1);

        assertTrue(block.timestamp > TERM_END);

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();
        uint256 prevYieldSharesIssued = term.yieldSharesIssued();
        uint256 prevLockedShares = prevYieldSharesIssued -
            prevYieldShareReserve;
        uint256 prevUnlockedYTBalance = term.balanceOf(UNLOCKED_YT_ID, user);
        uint256 prevPrincipalTokenBalance = term.balanceOf(TERM_END, user);

        uint256 pts = 10000e6;
        uint256 ptsAsLockedShares = CompoundV3TermHelper
            .principalTokensAsShares(term, TERM_END, pts);
        uint256 ptsAsUnderlying = term.yieldSharesAsUnderlying(
            ptsAsLockedShares
        );
        uint256 ptsAsUnlockedShares = CompoundV3TermHelper
            .underlyingAsUnlockedShares(term, ptsAsUnderlying);

        vm.startPrank(user);
        term.depositUnlocked(0, pts, TERM_END, user);
        vm.stopPrank();

        (
            uint256 underlyingReserve,
            uint256 yieldShareReserve,
            uint256 yieldShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve,
            uint256 accruedUnderlying
        ) = term.reserveDetails();
        uint256 yieldSharesIssued = term.yieldSharesIssued();
        uint256 lockedShares = yieldSharesIssued - yieldShareReserve;
        uint256 unlockedYTBalance = term.balanceOf(UNLOCKED_YT_ID, user);
        uint256 principalTokenBalance = term.balanceOf(TERM_END, user);

        assertEq(
            underlyingReserve,
            prevUnderlyingReserve,
            "underlyingReserve should be unchanged"
        );
        assertEq(
            yieldShareReserve,
            prevYieldShareReserve + ptsAsLockedShares,
            "yieldShareReserve should increase by the yield share value of principal tokens"
        );
        assertEq(
            yieldSharesIssued,
            prevYieldSharesIssued,
            "yieldSharesIsued should be unchanged"
        );
        assertApproxEqAbs(
            yieldShareReserveAsUnderlying,
            prevYieldShareReserveAsUnderlying + ptsAsUnderlying,
            1,
            "yieldShareReserveAsUnderlying should increase by the underlying value of the principal tokens"
        );
        assertApproxEqAbs(
            impliedUnderlyingReserve,
            prevImpliedUnderlyingReserve + ptsAsUnderlying,
            1,
            "impliedUnderlyingReserve should increase by the underlying value of the principal tokens"
        );
        assertEq(
            accruedUnderlying,
            prevAccruedUnderlying,
            "accruedUnderlying should be unchanged"
        );
        assertEq(
            unlockedYTBalance,
            prevUnlockedYTBalance + ptsAsUnlockedShares,
            "user unlocked yield token balance should increase by unlocked share value of principal tokens"
        );
        assertEq(
            principalTokenBalance,
            prevPrincipalTokenBalance - pts,
            "user principal token balance should decrease by amount of principal tokens"
        );
    }

    function test__convertUnlocked() public {
        uint256 inputDeposited = 1000000e6;

        vm.startPrank(user);
        term.depositUnlocked(inputDeposited, 0, 0, user);
        vm.stopPrank();

        (
            uint256 prevUnderlyingReserve,
            uint256 prevYieldShareReserve,
            uint256 prevYieldShareReserveAsUnderlying,
            uint256 prevImpliedUnderlyingReserve,
            uint256 prevAccruedUnderlying
        ) = term.reserveDetails();

        uint256 prevYieldSharesIssued = term.yieldSharesIssued();
        uint256 prevLockedShares = prevYieldSharesIssued -
            prevYieldShareReserve;
        uint256 prevUnlockedYTBalance = term.balanceOf(UNLOCKED_YT_ID, user);
        uint256 prevPrincipalTokenBalance = term.balanceOf(TERM_END, user);

        uint256 unlockedYts = 10000e6;
        uint256 unlockedYtsAsUnderlying = CompoundV3TermHelper
            .unlockedSharesAsUnderlying(term, unlockedYts);

        uint256 unlockedYtsAsLockedShares = term.underlyingAsYieldShares(
            unlockedYtsAsUnderlying
        );

        vm.startPrank(user);
        uint256[] memory assetIds = new uint256[](1);
        uint256[] memory assetAmounts = new uint256[](1);
        assetIds[0] = UNLOCKED_YT_ID;
        assetAmounts[0] = unlockedYts;
        term.lock(
            assetIds,
            assetAmounts,
            0,
            false,
            user,
            user,
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
        uint256 lockedShares = yieldSharesIssued - yieldShareReserve;
        uint256 unlockedYTBalance = term.balanceOf(UNLOCKED_YT_ID, user);
        uint256 principalTokenBalance = term.balanceOf(TERM_END, user);

        assertEq(
            underlyingReserve,
            prevUnderlyingReserve,
            "underlyingReserve should be unchanged"
        );
        assertEq(
            yieldShareReserve,
            prevYieldShareReserve - unlockedYtsAsLockedShares,
            "yieldShareReserve should decrease by the yield share value of the unlocked YTs"
        );

        assertEq(
            yieldSharesIssued,
            prevYieldSharesIssued,
            "yieldSharesIsued should be unchanged"
        );

        assertApproxEqAbs(
            yieldShareReserveAsUnderlying,
            prevYieldShareReserveAsUnderlying - unlockedYtsAsUnderlying,
            1,
            "yieldShareReserveAsUnderlying should decrease by the underlying value of the unlocked YTs"
        );
        assertApproxEqAbs(
            impliedUnderlyingReserve,
            prevImpliedUnderlyingReserve - unlockedYtsAsUnderlying,
            1,
            "impliedUnderlyingReserve should decrease by the underlying value of the unlocked YTs"
        );
        assertEq(
            accruedUnderlying,
            prevAccruedUnderlying,
            "accruedUnderlying should be unchanged"
        );
        assertEq(
            unlockedYTBalance,
            prevUnlockedYTBalance - unlockedYts,
            "user unlocked yield token balance should decrease by amount of unlocked YTs"
        );
    }
}
