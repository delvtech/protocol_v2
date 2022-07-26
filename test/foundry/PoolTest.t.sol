// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import { Pool } from "../../contracts/Pool.sol";
import { MockERC20Permit } from "../../contracts/mocks/MockERC20Permit.sol";
import { MockERC20YearnVault } from "../../contracts/mocks/MockERC20YearnVault.sol";
import { MockYieldAdapter } from "../../contracts/mocks/MockYieldAdapter.sol";

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract PoolTest is Test {
    Pool public pool;
    MockYieldAdapter public yieldAdapter;
    User public user1;
    MockERC20Permit public usdc;

    function setUp() public {
        // Contract initialization
        usdc = new MockERC20Permit("USDC", "USDC", 6);
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
        vm.prank(address(pool), address(pool));
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
        // Configure approval so that Pool can transfer usdc from User to itself
        vm.startPrank(address(user1));
        usdc.approve(address(pool), type(uint256).max);
        // registerPoolId
        pool.registerPoolId(poolId, underlyingIn, timeStretch, address(user1));
        vm.stopPrank();
        uint256 balanceAfter = usdc.balanceOf(address(user1));
        assertEq(balanceBefore, balanceAfter + underlyingIn);
    }
}
