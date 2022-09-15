// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import "forge-std/Test.sol";

import {ForwarderFactory} from "contracts/ForwarderFactory.sol";
import {MockERC20Permit} from "contracts/mocks/MockERC20Permit.sol";
import {MockTerm} from "contracts/mocks/MockTerm.sol";
import {MockPool} from "contracts/mocks/MockPool.sol";

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {ITerm} from "contracts/interfaces/ITerm.sol";

import {FixedPointMath} from "contracts/libraries/FixedPointMath.sol";
import {ElementError} from "contracts/libraries/Errors.sol";

import {ElementTest} from "test/ElementTest.sol";

contract PoolTest is ElementTest {
    ForwarderFactory factory;
    MockERC20Permit underlying;
    MockTerm term;
    MockPool pool;

    address user = makeAddress("user");
    address governance = makeAddress("governance");

    uint256 TRADE_FEE = 1;
    uint256 TERM_END;

    function setUp() public {
        factory = new ForwarderFactory();
        vm.warp(2000);
        vm.roll(2);
        TERM_END = block.timestamp + YEAR;
    }

    // ------------------- constructor unit tests ------------------ //
    // ------------------- name unit tests ------------------ //
    // ------------------- symbol unit tests ------------------ //
    // ------------------- registerPoolId unit tests ------------------ //

    struct RegisterPoolIdScenario {
        uint256 poolId;
        uint256 underlyingIn;
        uint32 tStretch;
        address recipient;
        uint16 maxTime;
        uint16 maxLength;
        string errorMsg;
        bytes4 errorSelector;
        uint256 totalSupply;
        uint256 sharesMinted;
        uint256 sharesValue;
        uint256 underlyingMintAmount;
        uint8 underlyingDecimals;
    }

    event PoolRegistered(uint256 indexed poolId);

    function test__registerPoolId__successCases(
        uint256 poolId,
        uint256 underlyingIn,
        uint32 tStretch,
        address recipient,
        uint16 maxTime,
        uint16 maxLength,
        uint256 sharesMinted,
        uint8 underlyingDecimals
    )
        public
    {
        vm.assume(poolId > block.timestamp && poolId != TERM_END + 1);
        // 1 billion assumed max underlying
        vm.assume(underlyingIn > 0 && underlyingIn <= 1_000_000_000e18);
        vm.assume(tStretch > 0);
        vm.assume(maxLength > 1);
        vm.assume(maxTime >= maxLength);
        vm.assume(underlyingDecimals > 0 && underlyingDecimals <= 18);

        // sharesMinted are expected to always be <= underlyingIn
        vm.assume(sharesMinted > 0 && sharesMinted <= underlyingIn);

        RegisterPoolIdScenario memory scene = RegisterPoolIdScenario(
            poolId,
            underlyingIn,
            tStretch,
            recipient,
            maxTime,
            maxLength,
            "",
            bytes4(0),
            0,
            sharesMinted,
            underlyingIn,
            underlyingIn,
            underlyingDecimals
        );

        vm.startPrank(user);
        setupRegisterPoolIdScenario(scene);
        validateRegisterPoolIdSuccessCase(scene);
        vm.stopPrank();
    }

    function test__registerPoolId__failureCases() public {
        RegisterPoolIdScenario[12] memory scenes = [
            // Term expired - pool id == block.timestamp
            RegisterPoolIdScenario({
                poolId: block.timestamp,
                underlyingIn: 1e18,
                tStretch: 10245,
                recipient: user,
                maxTime: 5,
                maxLength: 5,
                errorMsg: "",
                errorSelector: ElementError.TermExpired.selector,
                totalSupply: 0,
                sharesMinted: 0.9e18,
                sharesValue: 1e18,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 18
            }),
            // Term expired - pool id < block.timestamp
            RegisterPoolIdScenario({
                poolId: block.timestamp - 1,
                underlyingIn: 1e18,
                tStretch: 10245,
                recipient: user,
                maxTime: 5,
                maxLength: 5,
                errorMsg: "",
                errorSelector: ElementError.TermExpired.selector,
                totalSupply: 0,
                sharesMinted: 0.9e18,
                sharesValue: 1e18,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 18
            }),
            // Pool already initialized
            RegisterPoolIdScenario({
                poolId: TERM_END,
                underlyingIn: 1e18,
                tStretch: 10245,
                recipient: user,
                maxTime: 5,
                maxLength: 5,
                errorMsg: "",
                errorSelector: ElementError.PoolInitialized.selector,
                totalSupply: 1,
                sharesMinted: 0.9e18,
                sharesValue: 1e18,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 18
            }),
            // 0 Tstretch
            RegisterPoolIdScenario({
                poolId: TERM_END,
                underlyingIn: 1e18,
                tStretch: 0,
                recipient: user,
                maxTime: 5,
                maxLength: 5,
                errorMsg: "",
                errorSelector: ElementError.TimeStretchMustBeNonZero.selector,
                totalSupply: 0,
                sharesMinted: 0.9e18,
                sharesValue: 1e18,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 18
            }),
            // 0 underlying in
            RegisterPoolIdScenario({
                poolId: TERM_END,
                underlyingIn: 0,
                tStretch: 10245,
                recipient: user,
                maxTime: 5,
                maxLength: 5,
                errorMsg: "",
                errorSelector: ElementError.UnderlyingInMustBeNonZero.selector,
                totalSupply: 0,
                sharesMinted: 0.9e18,
                sharesValue: 1e18,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 18
            }),
            // not enough funds for transfer from
            RegisterPoolIdScenario({
                poolId: TERM_END,
                underlyingIn: 1e18,
                tStretch: 10245,
                recipient: user,
                maxTime: 5,
                maxLength: 5,
                errorMsg: "ERC20: insufficient-balance",
                errorSelector: bytes4(0),
                totalSupply: 0,
                sharesMinted: 0.9e18,
                sharesValue: 1e18,
                underlyingMintAmount: 0,
                underlyingDecimals: 18
            }),
            // 0 sharesMinted return from deposit causes divide by 0
            RegisterPoolIdScenario({
                poolId: TERM_END,
                underlyingIn: 1e18,
                tStretch: 10245,
                recipient: user,
                maxTime: 5,
                maxLength: 5,
                errorMsg: "EvmError: Revert", // FixedPointMath does assembly division
                errorSelector: bytes4(0),
                totalSupply: 0,
                sharesMinted: 0,
                sharesValue: 0,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 18
            }),
            // 0 maxLength initializeBuffer error
            RegisterPoolIdScenario({
                poolId: TERM_END,
                underlyingIn: 1e18,
                tStretch: 10245,
                recipient: user,
                maxTime: 1,
                maxLength: 0,
                errorMsg: "",
                errorSelector: ElementError.TWAROracle_IncorrectBufferLength.selector,
                totalSupply: 0,
                sharesMinted: 0.9e18,
                sharesValue: 1e18,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 18
            }),
            // 1 maxLength initializeBuffer error
            RegisterPoolIdScenario({
                poolId: TERM_END,
                underlyingIn: 1e18,
                tStretch: 10245,
                recipient: user,
                maxTime: 1,
                maxLength: 1,
                errorMsg: "",
                errorSelector: ElementError.TWAROracle_IncorrectBufferLength.selector,
                totalSupply: 0,
                sharesMinted: 0.9e18,
                sharesValue: 1e18,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 18
            }),
            // Min timestep error
            RegisterPoolIdScenario({
                poolId: TERM_END,
                underlyingIn: 1e18,
                tStretch: 10245,
                recipient: user,
                maxTime: 0,
                maxLength: 2,
                errorMsg: "",
                errorSelector: ElementError.TWAROracle_MinTimeStepMustBeNonZero.selector,
                totalSupply: 0,
                sharesMinted: 0.9e18,
                sharesValue: 1e18,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 18
            }),
            // already initialized buffer
            RegisterPoolIdScenario({
                poolId: TERM_END + 1,
                underlyingIn: 1e18,
                tStretch: 10245,
                recipient: user,
                maxTime: 5,
                maxLength: 5,
                errorMsg: "",
                errorSelector: ElementError.TWAROracle_BufferAlreadyInitialized.selector,
                totalSupply: 0,
                sharesMinted: 0.9e18,
                sharesValue: 1e18,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 18
            }),
            // sharesValue upperBound mu calc fixedPointMath scaled assembly division overflow
            RegisterPoolIdScenario({
                poolId: TERM_END,
                underlyingIn: 1e12,
                tStretch: 10245,
                recipient: user,
                maxTime: 5,
                maxLength: 5,
                errorMsg: "EvmError: Revert",
                errorSelector: bytes4(0),
                totalSupply: 0,
                sharesMinted: 1e12,
                sharesValue: ((type(uint256).max / 1e12) / 1e18) + 1,
                underlyingMintAmount: 1e18,
                underlyingDecimals: 6
            })
        ];

        vm.startPrank(user);

        for (uint256 i = 0; i < scenes.length; i++) {
            console.log("Pool.registerPoolId() Fail Scenario #%s", i);
            RegisterPoolIdScenario memory scene = scenes[i];
            setupRegisterPoolIdScenario(scene);

            expectRevert(scene.errorMsg, scene.errorSelector);
            pool.registerPoolId(
                scene.poolId, scene.underlyingIn, scene.tStretch, scene.recipient, scene.maxTime, scene.maxLength
            );
        }
        vm.stopPrank();
    }

    function setupRegisterPoolIdScenario(RegisterPoolIdScenario memory scene) internal {
        underlying = new MockERC20Permit("Test", "TEST", scene.underlyingDecimals);
        term = new MockTerm(
                factory.ERC20LINK_HASH(),
                address(factory),
                IERC20(underlying),
                governance
            );
        pool = new MockPool(
                ITerm(address(term)),
                IERC20(address(underlying)),
                TRADE_FEE,
                factory.ERC20LINK_HASH(),
                governance,
                address(factory)
            );

        underlying.approve(address(pool), type(uint256).max);
        underlying.mint(user, 1e18);

        term.setDepositReturnValues(0.9e18, 1e18);
        pool.registerPoolId(TERM_END + 1, 1e18, 10245, user, 5, 5);

        underlying.mint(user, scene.underlyingMintAmount);
        pool.setTotalSupply(scene.poolId, scene.totalSupply);

        term.setDepositReturnValues(scene.sharesMinted, scene.sharesValue);
    }

    function validateRegisterPoolIdSuccessCase(RegisterPoolIdScenario memory scene) internal {
        uint256 userUnderlyingBalance = underlying.balanceOf(user);
        uint256 userLpBalanceBefore = pool.balanceOf(scene.poolId, scene.recipient);
        uint256 poolTotalSupplyBefore = pool.totalSupply(scene.poolId);
        uint256 unlockedYTOnPoolBalanceBefore = term.balanceOf(term.UNLOCKED_YT_ID(), address(pool));

        vm.expectEmit(true, false, false, false);
        emit PoolRegistered(scene.poolId);

        uint256 mintedLpTokens = pool.registerPoolId(
            scene.poolId, scene.underlyingIn, scene.tStretch, scene.recipient, scene.maxTime, scene.maxLength
        );

        assertEq(
            underlying.balanceOf(user),
            userUnderlyingBalance - scene.underlyingIn,
            "user underlying balance should decrease by amount of underlyingIn"
        );

        (uint128 shares, uint128 bonds) = pool.reserves(scene.poolId);
        assertEq(shares, uint128(scene.sharesMinted), "reserve shares should equal minted shares");
        assertEq(bonds, 0, "reserve bonds should be 0");

        (,,, uint16 bufferMaxLength,) = pool.readMetadataParsed(scene.poolId);
        if (scene.maxTime > 0 || scene.maxLength > 0) {
            assertEq(bufferMaxLength, scene.maxLength, "Oracle should be initialized");
        } else {
            assertEq(bufferMaxLength, 0, "Oracle should not be initialized");
        }

        uint256 derivedMu =
            FixedPointMath.divDown(pool.normalize(scene.sharesValue), pool.normalize(scene.sharesMinted));
        (uint32 tStretch, uint224 mu) = pool.parameters(scene.poolId);
        assertEq(tStretch, scene.tStretch, "tStretch parameter should match input");
        assertEq(mu, derivedMu, "mu paramater should be derived correctly");

        uint256 poolTotalSupplyAfter = pool.totalSupply(scene.poolId);
        assertEq(
            poolTotalSupplyAfter - poolTotalSupplyBefore,
            scene.totalSupply + scene.sharesMinted,
            "should create sharesMinted amount of LP tokens"
        );

        uint256 userLpBalanceAfter = pool.balanceOf(scene.poolId, scene.recipient);
        assertEq(
            userLpBalanceAfter - userLpBalanceBefore, scene.sharesMinted, "LP tokens should be minted to the recipient"
        );

        uint256 unlockedYTOnPoolBalanceAfter = term.balanceOf(term.UNLOCKED_YT_ID(), address(pool));
        assertEq(
            unlockedYTOnPoolBalanceAfter - unlockedYTOnPoolBalanceBefore,
            scene.sharesMinted,
            "Unlocked shares should be minted to the pool"
        );

        assertEq(mintedLpTokens, scene.sharesMinted, "output value should equal minted shares");
    }
}
