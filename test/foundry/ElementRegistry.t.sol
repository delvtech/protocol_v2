// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "contracts/ForwarderFactory.sol";
import "contracts/Term.sol";
import "contracts/ElementRegistry.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "contracts/mocks/MockERC20YearnVault.sol";
import "contracts/mocks/MockPool.sol";
import "contracts/mocks/MockYieldAdapter.sol";
import "forge-std/Test.sol";
import { ElementTest } from "test/ElementTest.sol";

contract ElementRegistryTest is ElementTest {
    ForwarderFactory public factory;
    MockERC20Permit public token;
    MockERC20YearnVault public yearnVault;
    MockPool public pool;
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

        // deploy term registry and authorize user
        startHoax(address(owner));
        registry = new ElementRegistry(address(owner));
        registry.authorize(address(user));
        vm.stopPrank();
    }

    function testRegister() public {
        startHoax(address(user));
        registry.register(address(term), address(pool));
        assertEq(registry.getRegistryCount(), 1);
    }

    // test expected to fail when caller is not authorized
    function testFailRegisterTerm() public {
        address bad = makeAddress("bad");
        startHoax(address(bad));
        registry.register(address(term), address(pool));
    }

    // test expected to fail when the term in the pool contract differs from the term being registered
    function testFailRegisterTerm_poolDifferentTerm() public {
        startHoax(address(user));
        MockYieldAdapter newTerm = new MockYieldAdapter(
            address(yearnVault),
            governanceContract,
            linkerCodeHash,
            address(factory),
            token
        );
        Pool newPool = new MockPool(
            newTerm,
            token,
            tradeFee,
            linkerCodeHash,
            governanceContract,
            address(factory)
        );

        registry.register(address(term), address(newPool));
    }
}
