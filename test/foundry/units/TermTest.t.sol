// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "contracts/ForwarderFactory.sol";
import "contracts/Term.sol";
import "contracts/interfaces/IERC20.sol";
import "contracts/mocks/MockERC20Permit.sol";

contract TermTest is Test, Term {
    // -------------------       Mock Setup      --------------------- //

    ForwarderFactory _factory;
    IERC20 _token;

    // FIXME: Comment this hack.
    modifier setupDependencies() {
        _factory = new ForwarderFactory();
        _token = new MockERC20Permit("Test", "TEST", 18);
        _;
    }

    // FIXME: Comment this to explain what's happening.
    //
    // TODO: Add the ability to specify a different amount of decimals.
    constructor()
        setupDependencies
        Term(
            _factory.ERC20LINK_HASH(),
            address(_factory),
            _token,
            address(this)
        )
    {}

    function _convert(ShareState _state, uint256 _shares)
        internal
        override
        returns (uint256)
    {
        // FIXME: Implement this so that it's a useful mock.
        return 0;
    }

    function _deposit(ShareState _state)
        internal
        override
        returns (uint256, uint256)
    {
        // FIXME: Implement this so that it's a useful mock.
        return (0, 0);
    }

    function _underlying(uint256 _shares, ShareState _state)
        internal
        view
        override
        returns (uint256)
    {
        // FIXME: Implement this so that it's a useful mock.
        return 0;
    }

    function _withdraw(
        uint256 _shares,
        address _dest,
        ShareState _state
    ) internal override returns (uint256) {
        // FIXME: Implement this so that it's a useful mock.
        return 0;
    }

    // -------------------      Foundry Setup       ------------------ //

    function setUp() public {}
}
