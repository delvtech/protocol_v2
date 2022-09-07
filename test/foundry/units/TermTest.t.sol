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

    // ------------------- _parseAssetId unit tests ------------------ //

    function encodeAssetId(
        bool isYieldToken,
        uint256 startDate,
        uint256 expirationDate
    ) internal pure returns (uint256) {
        // FIXME: Is there not a way to cast from bool to uint anymore?
        return
            isYieldToken
                ? 1
                : (0 << 255) |
                    (uint128(startDate) << 128) |
                    uint128(expirationDate);
    }

    function testParseAssetId() public pure {
        bool[8] memory isYieldTokenInputs = [
            false,
            false,
            false,
            false,
            true,
            true,
            true,
            true
        ];
        uint256[8] memory startDateInputs = [
            uint256(0),
            0,
            15,
            43,
            0,
            0,
            35,
            435
        ];
        uint256[8] memory expirationDateInputs = [
            uint256(0),
            12,
            0,
            67,
            0,
            13,
            0,
            234
        ];

        for (uint256 i = 0; i < isYieldTokenInputs.length; i++) {
            (
                bool isYieldToken,
                uint256 startDate,
                uint256 expirationDate
            ) = _parseAssetId(
                    encodeAssetId(
                        isYieldTokenInputs[i],
                        startDateInputs[i],
                        expirationDateInputs[i]
                    )
                );

            assertEq(isYieldToken, isYieldTokenInputs[i]);
            assertEq(startDate, startDateInputs[i]);
            assertEq(expirationDate, expirationDateInputs[i]);
        }
    }
}
