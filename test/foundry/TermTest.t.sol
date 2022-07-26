// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./utils/Hevm.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/Term.sol";
import "contracts/mocks/TestERC20.sol";
import "contracts/interfaces/IERC20.sol";

contract User {
    // to be able to receive funds
    receive() external payable {} // solhint-disable-line no-empty-blocks
}

contract MockTerm is Term {
    constructor(
        bytes32 _linkerCodeHash,
        address _factory,
        IERC20 _token,
        address _owner
    ) Term(_linkerCodeHash, _factory, _token, _owner) {}

    function _deposit(ShareState)
        internal
        pure
        override
        returns (uint256, uint256)
    {
        return (0, 0);
    }

    /// @return the amount produced
    function _withdraw(
        uint256,
        address,
        ShareState
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _underlying(uint256, ShareState)
        internal
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function _convert(ShareState, uint256)
        internal
        pure
        override
        returns (uint256)
    {
        return 0;
    }
}

contract TermTest is Test {
    ForwarderFactory public ff;
    Term public term;
    TestERC20 public token;
    User public user;

    function setUp() public {
        ff = new ForwarderFactory();
        token = new TestERC20("Test Token", "tt", 18);
        user = new User();
        term = new MockTerm(
            ff.ERC20LINK_HASH(),
            address(ff),
            token,
            address(user)
        );
    }

    function testDeploy() public {
        // TODO: figure out why console.log isn't working
        console.log("term address %s", address(term));
        assertEq(IERC20(term.token()).name(), token.name());
    }
}
