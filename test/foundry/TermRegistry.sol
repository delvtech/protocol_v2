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

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract ElementRegistryTest is Test {
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

        // deploy term registry and authorize user
        startHoax(address(owner));
        registry = new ElementRegistry(address(owner));
        registry.authorize(address(user));
        vm.stopPrank();
    }

    function testRegisterTerm() public {
        startHoax(address(user));
        registry.registerTerm(term, pool, 1);
        assertEq(registry.getTermsCount(), 1);
    }

    // test expected to fail when caller is not authorized
    function testFailRegisterTerm() public {
        User bad = new User();
        startHoax(address(bad));
        registry.registerTerm(term, pool, 1);
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

        registry.registerTerm(term, newPool, 1);
    }
}
