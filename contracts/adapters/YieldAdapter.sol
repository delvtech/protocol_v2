// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract YieldAdapter {
    /// This is the address of an arbitrary "vault" contract which implicitly
    /// describes a contract which manages and exposes accounting logic for
    /// some yield generating "asset".
    address public immutable vault;

    /// The shareToken points to the token unit "shares" which reflect partial
    /// ownership over the entirety of assets contained in the "vault". In the
    /// majority of cases the shareToken contract is itself the vault but
    /// integrations may exist where shares are managed elsewhere.
    IERC20 public immutable shareToken;

    // This points to the token which the source contract "vault" wraps, e.g DAI
    IERC20 public immutable assetToken;

    constructor(
        address _vault,
        IERC20 _shareToken,
        IERC20 _assetToken
    ) {
        vault = _vault;
        shareToken = _shareToken;
        assetToken = _assetToken;
    }

    function deposit() external virtual returns (uint256, uint256);

    /// @return the amount produced
    function withdraw(
        uint256,
        address,
        uint256
    ) external virtual returns (uint256);

    // unit amounts of assetToken per 1 unit shareToken
    function pricePerShare(uint256 _amount) external virtual returns (uint256);
}
