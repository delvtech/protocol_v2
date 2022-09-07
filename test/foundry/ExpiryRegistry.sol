// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "contracts/ForwarderFactory.sol";
import "contracts/Term.sol";
import "contracts/TermRegistry.sol";
import "contracts/ExpiryRegistry.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "contracts/mocks/MockERC20YearnVault.sol";
import "contracts/mocks/MockPool.sol";
import "contracts/mocks/MockYieldAdapter.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract ExpiryRegistryTest is Test {
    ForwarderFactory public factory;
    MockERC20Permit public token;
    MockERC20YearnVault public yearnVault;
    MockPool public pool;
    MockYieldAdapter public term;
    TermRegistry public registry;
    ExpiryRegistry public expiryRegistry;
    User public owner;
    User public user;

    // constants
    bytes32 public linkerCodeHash = bytes32(0);
    address public governanceContract =
        address(0xEA674fdDe714fd979de3EdF0F56AA9716B898ec8);
    uint256 public tradeFee = 10;

    function setUp() public {
        owner = new User();
        user = new User();

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

        startHoax(address(term));
        term.setApprovalForAll(address(pool), true);
        vm.stopPrank();

        startHoax(address(owner));
        registry = new TermRegistry(address(owner));
        registry.authorize(address(user));
        expiryRegistry = new ExpiryRegistry(address(owner), registry);
        vm.stopPrank();

        startHoax(address(user));
        registry.registerTerm(term, pool, 1);
        vm.stopPrank();
    }

    function testCreateTerm() public {
        startHoax(address(expiryRegistry));
        // token.approve(term);

        token.mint(address(expiryRegistry), 200_000 * 1e18);
        token.approve(address(term), type(uint256).max);
        token.approve(address(pool), type(uint256).max);
        term.setApprovalForAll(address(pool), true);

        ExpiryRegistry.PoolConfig memory poolConfig = ExpiryRegistry.PoolConfig(
            10_000,
            0,
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
            1_000 * 1e18
        );

        // assertEq(registry.getTermsCount(), 1);
    }

    // function testCreateTerm_externalSeeder() public {
    //     // startHoax(address(expiryRegistry));
    //     // // token.approve(term);
    //     // token.mint(address(expiryRegistry), 200_000 * 1e18);
    //     // ExpiryRegistry.PoolConfig memory poolConfig = ExpiryRegistry.PoolConfig(
    //     //     10_000,
    //     //     0,
    //     //     0,
    //     //     0
    //     // );
    //     // expiryRegistry.createTerm(
    //     //     0,
    //     //     poolConfig,
    //     //     block.timestamp + 100_000,
    //     //     address(this),
    //     //     100_000,
    //     //     50_000,
    //     //     25_000
    //     // );
    //     // assertEq(registry.getTermsCount(), 1);
    // }

    // function testFailRegisterTerm() public {
    //     // User bad = new User();
    //     // startHoax(address(bad));
    //     // registry.registerTerm(term, pool, 1);
    // }

    // function testFailRegisterTerm_poolDifferentTerm() public {
    //     // startHoax(address(user));
    //     // MockYieldAdapter newTerm = new MockYieldAdapter(
    //     //     address(yearnVault),
    //     //     governanceContract,
    //     //     linkerCodeHash,
    //     //     address(factory),
    //     //     token
    //     // );
    //     // Pool newPool = new MockPool(
    //     //     newTerm,
    //     //     token,
    //     //     tradeFee,
    //     //     linkerCodeHash,
    //     //     governanceContract,
    //     //     address(factory)
    //     // );
    //     // registry.registerTerm(term, newPool, 1);
    // }
}
