// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { MockERC4626, ERC20 } from "contracts/mocks/MockERC4626.sol";
import { MockERC20Permit } from "contracts/mocks/MockERC20Permit.sol";

import { ERC4626Term, IERC4626 } from "contracts/ERC4626Term.sol";
import { Pool, ITerm, IERC20 } from "contracts/Pool.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";

import { ElementTest } from "../Utils.sol";

contract PoolTest is ElementTest {
    MockERC20Permit public USDC;
    MockERC4626 public yUSDC;
    ERC4626Term public term;
    Pool public pool;

    ForwarderFactory forwarderFactory;

    address user = mkAddr("user");
    address deployer = mkAddr("deployer");
    address governance = mkAddr("governance");

    uint256 public TERM_START = block.timestamp;
    uint256 public TERM_END = TERM_START + YEAR;
    uint256 public TRADE_FEE = 1;

    uint32 public T_STRETCH = 10245;

    struct Env {
        // ratio of vaultShares to underlying in yield source
        uint256 vaultSharePrice;
        // Amount of vault shares that have been issued previously
        uint256 vaultShareSupply;
        // Set max reserve
        uint256 maxReserve;
        // Amount of underlying to lock in the term once created
        uint256 underlyingToLock;
        // Amount of underlying to LP in the term once created
        uint256 underlyingToLP;
        // Percentage amount of time passed in TERM
        uint256 termDurationPassed;
        // Percentage increase of vault share price across term length
        uint256 averageYieldAcrossTerm;
    }

    function initEnv(Env memory env) public {
        vm.startPrank(deployer);

        USDC = new MockERC20Permit("USDC Coin", "USDC", 6);
        yUSDC = new MockERC4626(ERC20(address(USDC)));

        USDC.approve(address(yUSDC), type(uint256).max);

        USDC.mint(deployer, env.vaultShareSupply);
        yUSDC.deposit(env.vaultShareSupply, deployer);

        // TODO negative interest scenario in the vault
        USDC.mint(
            address(yUSDC),
            ((env.vaultShareSupply * 1e6) / env.vaultSharePrice) -
                env.vaultShareSupply
        );

        forwarderFactory = new ForwarderFactory();

        term = new ERC4626Term(
            IERC4626(address(yUSDC)),
            forwarderFactory.ERC20LINK_HASH(),
            address(forwarderFactory),
            env.maxReserve,
            governance
        );

        pool = new Pool(
            ITerm(address(term)),
            IERC20(address(USDC)),
            TRADE_FEE,
            forwarderFactory.ERC20LINK_HASH(),
            governance,
            address(forwarderFactory)
        );

        USDC.approve(address(term), type(uint256).max);
        USDC.approve(address(pool), type(uint256).max);

        USDC.mint(deployer, env.underlyingToLock + env.underlyingToLP);

        uint256[] memory assetIds;
        uint256[] memory assetAmounts;

        term.lock(
            assetIds,
            assetAmounts,
            env.underlyingToLock,
            false,
            deployer,
            deployer,
            TERM_START,
            TERM_END
        );

        pool.registerPoolId(
            TERM_END,
            env.underlyingToLP,
            T_STRETCH,
            user,
            5,
            5
        );

        uint256 avgYieldAcrossDuration = (env.averageYieldAcrossTerm *
            env.termDurationPassed) / 1e18;

        console.log("avgYieldAcrossDuration: %s", avgYieldAcrossDuration);

        uint256 preVaultSharePrice = yUSDC.previewRedeem(1e6);
        uint256 priceDiff = ((preVaultSharePrice * avgYieldAcrossDuration) /
            1e18);
        uint256 targetPrice = preVaultSharePrice + priceDiff;

        console.log("priceDiff: %s", priceDiff);
        console.log("targetPrice: %s", targetPrice);

        uint256 targetUnderlying = (yUSDC.totalSupply() * targetPrice) / 1e6;
        uint256 interestToAccrue = targetUnderlying -
            USDC.balanceOf(address(yUSDC));

        console.log("pre USDC: %s", USDC.balanceOf(address(yUSDC)));
        console.log("pre yUSDC: %s", yUSDC.totalSupply());
        console.log("pre price", preVaultSharePrice);

        USDC.mint(address(yUSDC), interestToAccrue);
        uint256 postVaultSharePrice = yUSDC.previewRedeem(1e6);

        console.log("post USDC: %s", USDC.balanceOf(address(yUSDC)));
        console.log("post yUSDC: %s", yUSDC.totalSupply());

        console.log("post price", postVaultSharePrice);

        assertEq(targetPrice, postVaultSharePrice);

        uint256 secondsPassed = ((TERM_END - block.timestamp) *
            env.termDurationPassed) / 1e18;

        vm.warp(block.timestamp + secondsPassed);
        vm.roll(secondsPassed / 12);

        vm.stopPrank();
    }
}
