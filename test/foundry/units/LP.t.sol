// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/mocks/MockLP.sol";
import "contracts/mocks/MockTerm.sol";
import "contracts/mocks/MockERC20Permit.sol";
import "test/foundry/Utils.sol";

contract LPTest is Test {
    address public user = vm.addr(0xDEAD_BEEF);

    ForwarderFactory public factory;
    MockTerm public term;
    MockERC20Permit public token;
    MockLP public lp;

    function setUp() public {
        // Set up the required Element contracts.
        factory = new ForwarderFactory();
        token = new MockERC20Permit("Test", "TEST", 18);
        term = new MockTerm(
            factory.ERC20LINK_HASH(),
            address(factory),
            IERC20(token),
            address(this)
        );
        lp = new MockLP(
            token,
            term,
            factory.ERC20LINK_HASH(),
            address(factory)
        );
    }

    // -------------------  _depositFromShares unit tests   ------------------ //

    // quick sanity test.  if pricePerShare is 1, then bonds and shares are equal, so we should see 2 shares get converted into 2 bonds
    function test__depositFromShares() public {
        uint256 poolId = 12345678;
        uint256 currentShares = 10 ether;
        uint256 currentBonds = 10 ether;
        uint256 depositedShares = 4 ether;
        uint256 pricePerShare = 1 ether;

        lp.setTotalSupply(10 ether, poolId);

        uint256 newLp = lp.depositFromSharesExternal(
            poolId,
            currentShares,
            currentBonds,
            depositedShares,
            pricePerShare,
            address(user)
        );

        assertEq(newLp, 2 ether);
    }
}
