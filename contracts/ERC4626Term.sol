// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "./TransactionCacheTerm.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IERC20.sol";
import "./MultiToken.sol";
import "./libraries/Errors.sol";

/// @title Term contract instance for the EIP-4626 Tokenized Vault Standard

/// @notice ERC4626Term is an implementation of the TransactionCacheTerm which is used
/// to interface the Element Protocol with yield bearing positions. This code
/// only handles external calls to the 4626 vault and the abstract TransactionCacheTerm
/// handles the rest.

// Inheritance Map -
//
//     Multi-token
//         |
//         v
//        Term
//         |
//         v
//    TransactionCache
//       |        \
//       v          v
//  CompoundTerm   4626Term <- YOU ARE HERE

/// @dev ERC4626Term implements an interface for the EIP-4626 Tokenized Vault
/// Standard. The contract is used internally by instances of Term.sol to `deposit`/`withdraw`
/// a users amount of underlying for/from "shares" which are used by the Element Protocol to derive
/// Principal and Yield Tokens.
/// The definition of "shares" is significant as it has two implied meanings and understanding them
/// is important in understanding the architecture of the protocol.

/// NOTE: To disambiguate ERC4626's conception of "shares" and the Element
/// Protocol's version, ERC4626's "shares" have been renamed here as "vaultShares"

contract ERC4626Term is TransactionCacheTerm {
    /// address of ERC4626 vault
    IERC4626 public immutable vault;

    /// @notice Associates the vault to the protocol and initializes the inheritance stack
    /// @param _vault Address of the ERC4626 vault
    /// @param _linkerCodeHash The hash of the erc20 linker contract deploy code
    /// @param _factory The factory which is used to deploy the linking contracts
    /// @param _maxReserve Upper bound of underlying which can be held in the
    ///                    reserve
    /// @param _owner this address will be made owner
    constructor(
        IERC4626 _vault,
        bytes32 _linkerCodeHash,
        address _factory,
        uint256 _maxReserve,
        address _owner
    )
        TransactionCacheTerm(
            _linkerCodeHash,
            _factory,
            _maxReserve,
            _vault.asset(),
            _owner
        )
    {
        vault = _vault;
        // This call is annoying but can't be cached before the init of the super
        IERC20(_vault.asset()).approve(address(_vault), type(uint256).max);
    }

    /// @notice Deposits into the 4626 vault then returns the number of shares created
    /// @param amount The tokens to send from this contract's balances
    /// @return shares The shares created by this deposit
    function _depositToYieldSource(uint256 amount)
        internal
        override
        returns (uint256 shares)
    {
        shares = vault.deposit(amount, address(this));
    }

    /// @notice Calls the 4626 vault to withdraw shares, the vault should send them to the destination address
    /// @param shares the 4626 vault shares to withdraw
    /// @param dest the address to send them to
    /// @return amount the amount of funds withdrawn
    function _withdrawFromYieldSource(uint256 shares, address dest)
        internal
        override
        returns (uint256 amount)
    {
        amount = vault.redeem(shares, dest, address(this));
    }

    /// @notice Calls into the 4626 vault to quote the amount which is received from a withdraw
    /// @param shares The shares to withdraw
    /// @return amount The vault which would be withdrawn if the shares are redeemed
    function _quoteWithdraw(uint256 shares)
        internal
        view
        override
        returns (uint256 amount)
    {
        amount = vault.previewRedeem(shares);
    }
}
