// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "contracts/ForwarderFactory.sol";
import "contracts/Term.sol";
import "contracts/ElementRegistry.sol";
import "contracts/ExpiryRegistry.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "contracts/mocks/MockERC20YearnVault.sol";
import "contracts/mocks/MockPool.sol";
import "contracts/mocks/MockYieldAdapter.sol";
import "forge-std/Test.sol";

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract ExpiryRegistryTest is Test {
    ExpiryRegistry public expiryRegistry;
    ForwarderFactory public factory;
    MockERC20Permit public token;
    MockERC20YearnVault public yearnVault;
    MockPool public pool;
    MockYieldAdapter public term;
    ElementRegistry public registry;
    User public owner;
    User public user;

    // constants
    bytes32 public linkerCodeHash = bytes32(0);
    address public governanceContract =
        address(0xEA674fdDe714fd979de3EdF0F56AA9716B898ec8);
    uint256 public tradeFee = 10;

    function setUp() public {
        // create mock accounts
        owner = new User();
        user = new User();

        // deploy mock contracts
        factory = new ForwarderFactory();
        token = new MockERC20Permit("Test Token", "TT", 18);
        yearnVault = new MockERC20YearnVault(address(token));
        term = new MockYieldAdapter(
            address(yearnVault),
            governanceContract,
            linkerCodeHash,
            address(factory),
            token
        );
        pool = new MockPool(
            term,
            token,
            tradeFee,
            linkerCodeHash,
            governanceContract,
            address(factory)
        );

        // give allowance to pool from term
        startHoax(address(term));
        term.setApprovalForAll(address(pool), true);
        vm.stopPrank();

        // setup term registry and expiry registry
        startHoax(address(owner));

        // term registry
        registry = new ElementRegistry(address(owner));
        registry.authorize(address(user));

        // expiry registry
        expiryRegistry = new ExpiryRegistry(address(owner), registry);
        expiryRegistry.authorize((address(expiryRegistry)));
        vm.stopPrank();

        // register a new term in the term registry
        startHoax(address(user));
        registry.registerTerm(term, pool);
        vm.stopPrank();

        // token approvals for expiryRegistry
        startHoax(address(expiryRegistry));
        token.approve(address(term), type(uint256).max);
        token.approve(address(pool), type(uint256).max);
        term.setApprovalForAll(address(pool), true);
        vm.stopPrank();
    }

    function testCreateTerm() public {
        startHoax(address(expiryRegistry));

        // give expiryRegistry tokens
        token.mint(address(expiryRegistry), 200_000 * 1e18);

        // create new term with liquidity
        ExpiryRegistry.PoolConfig memory poolConfig = ExpiryRegistry.PoolConfig(
            10_000,
            0,
            0
        );
        expiryRegistry.createTerm(
            0,
            poolConfig,
            block.timestamp + 100_000,
            address(expiryRegistry),
            100_000 * 1e18,
            1_000 * 1e18,
            1_000 * 1e18,
            0
        );

        // assert expiries have been registered
        assertEq(expiryRegistry.getExpiriesCount(0), 1);
    }

    function testCreateTerm_externalSeeder() public {
        // create new seeder account
        User seeder = new User();

        // mint and set token approvals for seeder
        startHoax(address(seeder));
        token.mint(address(seeder), 200_000 * 1e18);
        token.approve(address(term), type(uint256).max);
        token.approve(address(pool), type(uint256).max);
        token.approve(address(expiryRegistry), type(uint256).max);
        term.setApprovalForAll(address(pool), true);
        vm.stopPrank();

        startHoax(address(expiryRegistry));
        uint256 expiry = block.timestamp + 100_000;
        // create new term with liquidity using external seeder
        ExpiryRegistry.PoolConfig memory poolConfig = ExpiryRegistry.PoolConfig(
            10_000,
            0,
            0
        );
        expiryRegistry.createTerm(
            0,
            poolConfig,
            expiry,
            address(seeder),
            100_000 * 1e18,
            1_000 * 1e18,
            1_000 * 1e18,
            0
        );

        // assert expiries have been registered
        assertEq(expiryRegistry.getExpiriesCount(0), 1);

        // assert that seeder account is properly accredited for LP and any excess capital
        assertGt(pool.balanceOf(expiry, address(seeder)), 0);
        assertGt(term.balanceOf(expiry, address(seeder)), 0);
    }
}
