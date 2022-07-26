// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import { Hevm } from "./utils/Hevm.sol";
import { Pool } from "../../contracts/Pool.sol";
import { TestERC20 } from "../../contracts/mocks/TestERC20.sol";
import { MockERC20YearnVault } from "../../contracts/mocks/MockERC20YearnVault.sol";
import { MockYieldAdapter } from "../../contracts/mocks/MockYieldAdapter.sol";

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract PoolTest is Test {
    Pool internal pool;
    MockYieldAdapter internal yieldAdapter;
    User internal user1;
    TestERC20 internal usdc;
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        // Contract initialization
        usdc = new TestERC20("USDC", "USDC", 6);
        address governanceContract = address(1);
        MockERC20YearnVault yearnVault = new MockERC20YearnVault(address(usdc));
        bytes32 linkerCodeHash = bytes32(0);
        address forwarderFactory = address(1);
        yieldAdapter = new MockYieldAdapter(
            address(yearnVault),
            governanceContract,
            linkerCodeHash,
            forwarderFactory,
            usdc
        );
        uint256 tradeFee = 10;
        bytes32 erc20ForwarderCodeHash = bytes32(0);
        address erc20ForwarderFactory = address(1);
        pool = new Pool(
            yieldAdapter,
            usdc,
            tradeFee,
            erc20ForwarderCodeHash,
            governanceContract,
            erc20ForwarderFactory
        );

        // Configure approval so that YieldAdapter(term) can transfer usdc from Pool to itself
        hevm.prank(address(pool), address(pool));
        usdc.approve(address(yieldAdapter), type(uint256).max);

        // Configure user1
        user1 = new User();
    }

    function testRegisterPoolId() public {
        uint256 balanceBefore = 100;
        usdc.mint(address(user1), balanceBefore);
        uint256 poolId = block.timestamp + 1000;
        uint256 underlyingIn = 1;
        uint32 timeStretch = 1;
        address recipient = address(user1);
        // Configure approval so that Pool can transfer usdc from User to itself
        hevm.startPrank(address(user1));
        usdc.approve(address(pool), type(uint256).max);
        // registerPoolId
        pool.registerPoolId(poolId, underlyingIn, timeStretch, address(user1));
        hevm.stopPrank();
        uint256 balanceAfter = usdc.balanceOf(address(user1));
        assertEq(balanceBefore, balanceAfter + underlyingIn);
    }
}
