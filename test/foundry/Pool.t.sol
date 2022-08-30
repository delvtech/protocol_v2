// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { MockERC4626, ERC20 } from "contracts/mocks/MockERC4626.sol";
import { MockERC20Permit } from "contracts/mocks/MockERC20Permit.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { ERC4626Term, IERC4626 } from "contracts/ERC4626Term.sol";
import { Pool, ITerm, IERC20, FixedPointMath, ElementError } from "contracts/Pool.sol";

import "./Utils.sol";

contract PoolTest is Test {
    MockERC20Permit public USDC;
    MockERC4626 public yUSDC;
    ERC4626Term public term;
    Pool public pool;

    uint256 public constant YEAR = (365 * 24 * 60 * 60);

    uint256 public TERM_START;
    uint256 public TERM_END;

    address deployer = vm.addr(0xDE9107E4);
    address user = vm.addr(0x02E4);

    uint32 T_STRETCH = 10245;

    function setUp() public {
        /// Initialize underlying token
        USDC = new MockERC20Permit("USDC Coin", "USDC", 6);
        /// Initialize Vault
        yUSDC = new MockERC4626(ERC20(address(USDC)));

        vm.label(deployer, "deployer");
        vm.label(user, "user");

        startHoax(deployer);

        /// Create term contract for vault
        ForwarderFactory forwarderFactory = new ForwarderFactory();
        term = new ERC4626Term(
            IERC4626(address(yUSDC)),
            forwarderFactory.ERC20LINK_HASH(),
            address(forwarderFactory),
            100_000e6,
            address(this)
        );

        /// Set initial price in term
        USDC.mint(deployer, 200_000_000e6);
        USDC.approve(address(term), type(uint256).max);

        // Define the start and end dates for the term
        TERM_START = block.timestamp;
        TERM_END = TERM_START + YEAR;

        uint256[] memory assetIds;
        uint256[] memory assetAmounts;

        term.lock(
            assetIds,
            assetAmounts,
            90_000_000e6,
            false,
            address(this),
            address(this),
            TERM_START,
            TERM_END
        );
        term.depositUnlocked(90_000_000e6, 0, 0, address(this));

        USDC.transfer(address(yUSDC), 20_000_000e6);

        pool = new Pool(
            ITerm(address(term)),
            IERC20(address(USDC)),
            1,
            forwarderFactory.ERC20LINK_HASH(),
            deployer,
            address(forwarderFactory)
        );

        vm.stopPrank();
        startHoax(user);
        // Give the user some USDC
        USDC.mint(user, 100_000e6);
        USDC.approve(address(pool), type(uint256).max);
    }

    function test__initialState() public {
        assertEq(yUSDC.totalSupply(), 179_950_000e6);
        assertApproxEqAbs(yUSDC.convertToShares(1e6), 0.9e6, 50);
        assertEq(USDC.balanceOf(address(term)), term.targetReserve());

        (uint32 pool_tStretch, uint224 pool_mu) = pool.parameters(TERM_END);
        assertEq(pool_tStretch, 0);
        assertEq(pool_mu, 0);

        (uint128 shares, uint128 bonds) = pool.reserves(TERM_END);
        assertEq(shares, 0);
        assertEq(bonds, 0);
    }

    ////////////////////////////////////////////////////////////////////////////
    ///////
    ///////////////////////// Pool.registerPoolId() ////////////////////////////
    /////////////////////////                       ////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    // success case - no oracle initialization
    function test__registerPoolId__no_oracle_init() public {
        uint256 underlying = 10_000e6;

        uint256 userUnderlyingPreBalance = USDC.balanceOf(user);
        uint256 userLpPreBalance = pool.balanceOf(TERM_END, user);

        (uint128 preShares, uint128 preBonds) = pool.reserves(TERM_END);

        uint256 estMintedShares = Utils.underlyingAsUnlockedShares(
            term,
            underlying
        );
        uint256 estMu = FixedPointMath.divDown(
            underlying * 10e12,
            estMintedShares * 10e12
        );

        uint256 sharesMinted = pool.registerPoolId(
            TERM_END,
            underlying,
            T_STRETCH,
            user,
            0,
            0
        );

        uint256 userUnderlyingPostBalance = USDC.balanceOf(user);
        uint256 userLpPostBalance = pool.balanceOf(TERM_END, user);

        uint256 userUnderlyingDiff = userUnderlyingPreBalance -
            userUnderlyingPostBalance;
        uint256 userLpDiff = userLpPostBalance - userLpPreBalance;

        // User balances should be changed as expected
        assertEq(userUnderlyingDiff, underlying);
        assertEq(userLpDiff, estMintedShares);
        assertEq(sharesMinted, estMintedShares);

        // Shares should be added to the pool reserves
        (uint128 postShares, uint128 postBonds) = pool.reserves(TERM_END);
        assertEq(postShares - preShares, estMintedShares);
        assertEq(preBonds, postBonds);

        // buffer should not be initialized
        (, , , uint16 bufferMaxLength, ) = pool.readMetadataParsed(TERM_END);
        assertEq(bufferMaxLength, 0);

        // Pool parameters should be set correctly
        (uint32 tStretch, uint224 mu) = pool.parameters(TERM_END);
        assertEq(tStretch, T_STRETCH);
        assertEq(mu, estMu);
    }

    // success case - initialize oracle
    function test__registerPoolId__oracle_init() public {
        pool.registerPoolId(TERM_END, 10_000e6, T_STRETCH, user, 5, 5);

        // buffer should be initialized
        (, , , uint16 bufferMaxLength, ) = pool.readMetadataParsed(TERM_END);
        assertEq(bufferMaxLength, 5);
    }

    // error case - register pool past expiry
    function test__registerPoolId__beyond_expiry() public {
        // Fast forward to end of term + 1 second
        vm.warp(TERM_END + 1);
        vm.expectRevert(ElementError.TermExpired.selector);

        pool.registerPoolId(TERM_END, 10_000e6, T_STRETCH, user, 5, 5);
    }

    // error case - pool already initialized
    function test__registerPoolId__pool_initialized() public {
        pool.registerPoolId(TERM_END, 10_000e6, T_STRETCH, user, 5, 5);

        vm.expectRevert(ElementError.PoolInitialized.selector);

        pool.registerPoolId(TERM_END, 10_000e6, T_STRETCH, user, 5, 5);
    }

    // error case - zero t-stretch
    function test__registerPoolId__zero_tStretch() public {
        vm.expectRevert(ElementError.TimeStretchMustBeNonZero.selector);

        pool.registerPoolId(TERM_END, 10_000e6, 0, user, 5, 5);
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
}
