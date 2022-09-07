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

    // @notice Deploys a ForwarderFactory and a ERC20 token so that we can
    //         provide arguments to the Term constructor in this contract's
    //         constructor.
    modifier setupDependencies() {
        _factory = new ForwarderFactory();
        _token = new MockERC20Permit("Test", "TEST", 18);
        _;
    }

    // @notice This contract inherits from Term. This is a convenient
    //         alternative to creating a mock Term contract that exposes all
    //         of the internal functions as external functions that still
    //         allows us to access the state and test the internal functions.
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
