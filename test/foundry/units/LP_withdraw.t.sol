// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/mocks/MockLP.sol";
import "contracts/mocks/MockTerm.sol";
import "contracts/mocks/MockERC20Permit.sol";

import { ElementTest } from "test/ElementTest.sol";
import { Utils } from "test/Utils.sol";

contract LPTest is ElementTest {
    uint256 internal constant _UNLOCKED_TERM_ID = 1 << 255;
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

    // -------------------  withdraw unit tests   ------------------ //

    // should withdraw userShares and userBonds
    function test_withdraw() public {
        uint256 poolId = 0;
        uint256 amount = 1 ether;
        address destination = address(user);
        uint256 userShares = 1 ether;

        // try case where bonds do and don't transfer to the user
        uint256[] memory testCases = new uint256[](2);
        testCases[0] = 0;
        testCases[1] = 1 ether;

        // Set the address.
        startHoax(user);

        for (uint256 i; i < testCases.length; i++) {
            uint256 userBonds = testCases[i];
            lp.setWithdrawToSharesReturnValues(userShares, userBonds);
            lp.setDepositFromSharesReturnValue(1 ether);
            term.setUserBalance(poolId, address(lp), userBonds);

            expectStrictEmit();
            emit WithdrawToShares(
                poolId,
                1 ether, // amount
                destination // source
            );

            expectStrictEmit();
            emit Unlock(
                destination,
                _UNLOCKED_TERM_ID, // tokenId
                userShares // amount
            );

            if (userBonds != 0) {
                expectStrictEmit();
                emit TransferSingle(
                    address(lp), // caller
                    address(lp), // from
                    address(user), // to
                    poolId, // tokenId
                    userBonds // amount
                );
            }

            lp.withdraw(poolId, amount, destination);
        }
    }

    event WithdrawToShares(uint256 poolId, uint256 amount, address source);
    event Unlock(address destination, uint256 tokenId, uint256 amount);
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );
}
