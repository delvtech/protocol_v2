// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../Term.sol";

contract MockTerm is Term {
    constructor(
        bytes32 _linkerCodeHash,
        address _factory,
        IERC20 _token,
        address _owner
    ) Term(_linkerCodeHash, _factory, _token, _owner) {}

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

    function parseAssetIdExternal(uint256 _assetId)
        external
        view
        returns (
            bool,
            uint256,
            uint256
        )
    {
        return _parseAssetId(_assetId);
    }
}
