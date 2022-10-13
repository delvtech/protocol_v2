// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "contracts/ForwarderFactory.sol";
import "contracts/Term.sol";
import "contracts/ElementRegistry.sol";
import "contracts/Pool.sol";
import "contracts/TermRegistry.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "contracts/mocks/MockERC20YearnVault.sol";
import "contracts/mocks/MockYieldAdapter.sol";
import "forge-std/Test.sol";
import { ElementTest } from "test/ElementTest.sol";

contract TermRegistryTest is ElementTest {
    TermRegistry public termRegistry;
    ForwarderFactory public factory;
    MockERC20Permit public token;
    MockERC20YearnVault public yearnVault;
    Pool public pool;
    MockYieldAdapter public term;
    ElementRegistry public registry;
    address public user = makeAddress("user");
    address public owner = makeAddress("owner");

    // constants
    bytes32 public linkerCodeHash = bytes32(0);
    address public governanceContract =
        address(0xEA674fdDe714fd979de3EdF0F56AA9716B898ec8);
    uint256 public tradeFee = 10;

    function setUp() public {
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
        pool = new Pool(
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
        termRegistry = new TermRegistry(address(owner), registry);
        termRegistry.authorize((address(termRegistry)));
        vm.stopPrank();

        // register a new term in the term registry
        startHoax(address(user));
        registry.register(address(term), address(pool));
        vm.stopPrank();

        // token approvals for termRegistry
        startHoax(address(termRegistry));
        token.approve(address(term), type(uint256).max);
        token.approve(address(pool), type(uint256).max);
        term.setApprovalForAll(address(pool), true);
        vm.stopPrank();
    }

    function testCreateTerm() public {
        startHoax(address(termRegistry));

        // give termRegistry tokens
        token.mint(address(termRegistry), 200_000 * 1e18);

        // create new term with liquidity
        TermRegistry.PoolConfig memory poolConfig = TermRegistry.PoolConfig(
            10_000,
            0,
            0
        );
        termRegistry.createTerm(
            0,
            poolConfig,
            block.timestamp + 100_000,
            100_000 * 1e18,
            1_000 * 1e18,
            1_000 * 1e18,
            0
        );

        // assert expiries have been registered
        assertEq(termRegistry.getExpiriesCount(0), 1);
    }
}
