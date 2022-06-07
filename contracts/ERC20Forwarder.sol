// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import "./interfaces/IERC20.sol";
import "./interfaces/IMultiToken.sol";
import "./interfaces/IForwarderFactory.sol";

// This ERC20 forwarder forwards calls through an ERC20 compliant interface
// to move the sub tokens in our multi token contract. This enables our
// multitoken which are 'ERC1150' like to behave ike ERC20 in integrating
// protocols.
// It is a premissionlessly deployed bridge which is linked to the main contract
// by a create2 deployment validation so MUST be deployed by the right factory.
contract ERC20Forwarder is IERC20 {
    // The contract which contains the actual state for this 'ERC20'
    IMultiToken public immutable token;
    // The ID for this contract's 'ERC20' as a sub token of the main token
    uint256 public immutable tokenId;

    /// @notice Constructs this contract by initializing the immutables
    /// @dev To give the contract a constant deploy code hash we call back
    ///      into the factory to load info instead of using calldata.
    constructor() {
        // The deployer is the factory
        IForwarderFactory factory = IForwarderFactory(msg.sender);
        // We load the data we need to init
        (token, tokenId) = factory.getDeployDetails();
    }

    /// @notice Returns the decimals for this 'ERC20', we are opinionated
    ///         so we just return 18 in all cases
    /// @return Always 18
    function decimals() external pure override returns (uint8) {
        return (18);
    }

    /// @notice Returns the name of this sub token by calling into the
    ///         main token to load it.
    /// @return Returns the name of this token
    function name() external view override returns (string memory) {
        return (token.name(tokenId));
    }

    /// @notice Returns the symbol of this sub token by calling into the
    ///         main token to load it.
    /// @return Returns the symbol of this token
    function symbol() external view override returns (string memory) {
        return (token.symbol(tokenId));
    }

    /// @notice Returns the balance of this sub token through an ERC20 compliant
    ///         interface.
    /// @return The balance of the queried account.
    function balanceOf(address who) external view override returns (uint256) {
        return (token.balanceOf(tokenId, who));
    }

    /// @notice Loads the allowance information for an owner spender pair.
    ///         If spender is approved for all tokens in the main contract
    ///         it will return Max(uint256) otherwise it returns the allowance
    ///         the allowance for just this asset.
    /// @param owner The account who's tokens would be spent
    /// @param spender The account who might be able to spend tokens
    /// @return The amount of the owner's tokens the spender can spend
    function allowance(address owner, address spender)
        external
        view
        override
        returns (uint256)
    {
        // If the owner is approved for all they can spend an unlimited amount
        if (token.isApprovedForAll(owner, spender)) {
            return type(uint256).max;
        } else {
            // otherwise they can only spend up the their per token approval for
            // the owner
            return token.perTokenApprovals(tokenId, owner, spender);
        }
    }

    /// @notice Sets an approval for just this sub-token for the caller in the main token
    /// @param spender The address which can spend tokens of the caller
    /// @param amount The amount which the spender is allowed to spend, if it is
    ///               set to uint256.max it is infinite and will not be reduced by transfer.
    /// @return True if approval successful, false if not. The contract also reverts
    ///         on failure so only true is possible.
    function approve(address spender, uint256 amount) external returns (bool) {
        // The main token handles the internal approval logic
        token.setApprovalBridge(tokenId, spender, amount, msg.sender);
        // Emit a ERC20 compliant approval event
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Forwards a call to transfer from the msg.sender to the recipient.
    /// @param recipient The recipient of the token transfer
    /// @param amount The amount of token to transfer
    /// @return True if transfer successful, false if not. The contract also reverts
    ///         on failed transfer so only true is possible.
    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        token.transferFromBridge(
            tokenId,
            msg.sender,
            recipient,
            amount,
            msg.sender
        );
        // Emits an ERC20 compliant transfer event
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Forwards a call to transferFrom to move funds from an owner to a recipient
    /// @param source The source of the tokens to be transferred
    /// @param recipient The recipient of the tokens
    /// @param amount The amount of tokens to be transferred
    /// @return Returns true for success false for failure, also reverts on fail, so will
    ///         always return true.
    function transferFrom(
        address source,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        // The token handles the approval logic checking and transfer
        token.transferFromBridge(
            tokenId,
            source,
            recipient,
            amount,
            msg.sender
        );
        // Emits an ERC20 compliant transfer event
        emit Transfer(source, recipient, amount);
        return true;
    }
}
