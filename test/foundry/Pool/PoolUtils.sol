// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import "forge-std/Test.sol";

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

    address deployer = mkAddr("deployer");
    address user = mkAddr("user");
    address governance = mkAddr("governance");

    uint256 public TERM_START = block.timestamp;
    uint256 public TERM_END = TERM_START + YEAR;
    uint32 public T_STRETCH = 10245;
    uint256 public TRADE_FEE = 1;

    function setUp() public {
        vm.startPrank(deployer);

        USDC = new MockERC20Permit("USDC Coin", "USDC", 6);
        yUSDC = new MockERC4626(ERC20(address(USDC)));

        forwarderFactory = new ForwarderFactory();

        uint256[] memory assetIds;
        uint256[] memory assetAmounts;

        term = new ERC4626Term(
            IERC4626(address(yUSDC)),
            forwarderFactory.ERC20LINK_HASH(),
            address(forwarderFactory),
            100_000e6,
            address(this)
        );

        pool = new Pool(
            ITerm(address(term)),
            IERC20(address(USDC)),
            TRADE_FEE,
            forwarderFactory.ERC20LINK_HASH(),
            governance,
            address(forwarderFactory)
        );

        USDC.mint(deployer, 200_000_000e6);
        USDC.approve(address(term), type(uint256).max);

        term.lock(
            assetIds,
            assetAmounts,
            90_000_000e6,
            false,
            deployer,
            deployer,
            TERM_START,
            TERM_END
        );

        term.depositUnlocked(90_000_000e6, 0, 0, address(this));

        vm.stopPrank();
        vm.startPrank(user);

        USDC.mint(user, 100_000e6);
        USDC.approve(address(pool), type(uint256).max);
    }
}
