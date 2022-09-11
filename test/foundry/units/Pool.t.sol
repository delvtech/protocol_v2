// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/console2.sol";

import {ForwarderFactory} from "contracts/ForwarderFactory.sol";
import {MockERC20Permit} from "contracts/mocks/MockERC20Permit.sol";
import {MockTerm} from "contracts/mocks/MockTerm.sol";
import {MockPool} from "contracts/mocks/MockPool.sol";

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {ITerm} from "contracts/interfaces/ITerm.sol";

import {FixedPointMath} from "contracts/libraries/FixedPointMath.sol";
import {ElementError} from "contracts/libraries/Errors.sol";

import {ElementTest} from "../ElementTest.sol";

contract PoolTest is ElementTest {
    ForwarderFactory factory;
    MockERC20Permit underlying;
    MockTerm term;
    MockPool pool;

    address user = _mkAddr("user");
    address governance = _mkAddr("governance");

    uint256 TRADE_FEE = 1;

    function setUp() public {
        factory = new ForwarderFactory();
        vm.warp(2000);
        vm.roll(2);
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

    function test__registerPoolId() public {
        RegisterPoolIdScenario[6] memory scenes = [
            /////////////////////
            /// Success cases ///
            /////////////////////

            // Standard input
            // RegisterPoolIdScenario({
            //     poolId: block.timestamp + YEAR,
            //     underlyingIn: 1e18,
            //     tStretch: 10245,
            //     recipient: user,
            //     maxTime: 5,
            //     maxLength: 5,
            //     errorMsg: "",
            //     errorSelector: bytes4(0),
            //     totalSupply: 0,
            //     sharesMinted: 0.9e18,
            //     sharesValue: 1e18,
            //     underlyingMintAmount: 1e18,
            //     underlyingDecimals: 18
            // }),
            /////////////////////
            /// Failure cases ///
            /////////////////////

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
                poolId: block.timestamp + YEAR,
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
                poolId: block.timestamp + YEAR,
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
                poolId: block.timestamp + YEAR,
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
                poolId: block.timestamp + YEAR,
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
            })
            // Divide by 0 mu calculation
            // RegisterPoolIdScenario({
            //     poolId: block.timestamp + YEAR,
            //     underlyingIn: 1e18,
            //     tStretch: 10245,
            //     recipient: user,
            //     maxTime: 5,
            //     maxLength: 5,
            //     errorMsg: "divide by zero",
            //     errorSelector: bytes4(0),
            //     totalSupply: 0,
            //     sharesMinted: 0,
            //     sharesValue: 0,
            //     underlyingMintAmount: 1e18,
            //     underlyingDecimals: 18
            // })
        ];

        vm.startPrank(user);

        for (uint256 i = 0; i < scenes.length; i++) {
            console2.log("Pool.registerPoolId() Scenario #%s", i);

            RegisterPoolIdScenario memory scene = scenes[i];
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
            underlying.mint(user, scene.underlyingMintAmount);
            pool.setTotalSupply(scene.poolId, scene.totalSupply);
            term.setDepositReturnValues(scene.sharesMinted, scene.sharesValue);

            if (shouldExpectFailCase(scene.errorMsg, scene.errorSelector)) {
                pool.registerPoolId(
                    scene.poolId, scene.underlyingIn, scene.tStretch, scene.recipient, scene.maxTime, scene.maxLength
                );
            } else {
                validateRegisterPoolIdSuccessCase(scene);
            }
        }
        vm.stopPrank();
    }

    function validateRegisterPoolIdSuccessCase(RegisterPoolIdScenario memory scene) internal {
        uint256 userUnderlyingBalance = underlying.balanceOf(user);

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

        assertEq(
            pool.totalSupply(scene.poolId),
            scene.totalSupply + scene.sharesMinted,
            "should create sharesMinted amount of LP tokens"
        );
        assertEq(
            pool.balanceOf(scene.poolId, scene.recipient),
            scene.sharesMinted,
            "LP tokens should be minted to the recipient"
        );

        assertEq(mintedLpTokens, scene.sharesMinted, "output value should equal minted shares");
    }
}
