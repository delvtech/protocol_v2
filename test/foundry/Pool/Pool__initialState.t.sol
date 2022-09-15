// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { MockERC4626, ERC20 } from "contracts/mocks/MockERC4626.sol";
import { MockERC20Permit } from "contracts/mocks/MockERC20Permit.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { ERC4626Term, IERC4626 } from "contracts/ERC4626Term.sol";
import { Pool, ITerm, IERC20, FixedPointMath, ElementError } from "contracts/Pool.sol";

import { PoolTest } from "test/Pool/PoolUtils.sol";

contract PoolTest__initialState is PoolTest {
    // Reserves should be empty
    function test__reserves() public {
        (uint128 shares, uint128 bonds) = pool.reserves(TERM_END);
        assertEq(shares, 0);
        assertEq(bonds, 0);
    }

    // Paramaters should not be initialised
    function test__parameters() public {
        (uint32 tStretch, uint224 mu) = pool.parameters(TERM_END);
        assertEq(tStretch, 0);
        assertEq(mu, 0);
    }

    function test__governance_settings() public {
        (uint128 feesInShares, uint128 feesInBonds) = pool.governanceFees(
            TERM_END
        );
        assertEq(feesInShares, 0);
        assertEq(feesInBonds, 0);

        assertEq(pool.governanceFeePercent(), 0);
        assertEq(pool.governanceContract(), governance);
    }

    // Trade fee should match argument in constructor
    function test__tradeFee() public {
        assertEq(pool.tradeFee(), TRADE_FEE);
    }

    // governance address must be authorized
    function test__governance_is_authorized() public {
        assertTrue(pool.authorized(governance));
    }

    // governance must be owner
    function test__owner() public {
        assertEq(pool.owner(), governance);
    }

    // Pool must have max approval for the underlying token
    function test__term_is_approved() public {
        assertEq(
            USDC.allowance(address(pool), address(term)),
            type(uint256).max
        );
    }

    // Should fail with "RestrictedZeroAddress()"
    function testFail__non_zero_governance_address() public {
        pool = new Pool(
            ITerm(address(term)),
            IERC20(address(USDC)),
            TRADE_FEE,
            forwarderFactory.ERC20LINK_HASH(),
            address(0),
            address(forwarderFactory)
        );
    }
}
