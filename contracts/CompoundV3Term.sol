// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "./TransactionCacheTerm.sol";
import "./interfaces/ICompoundV3.sol";

/// Docs: https://c3-docs.compound.finance/
contract CompoundV3Term is TransactionCacheTerm {
    /// This implements the Compound Comet protocol as a yield source via
    /// the TransactionCacheTerm.

    // Inheritance Map -
    //
    //                        Multi-token
    //                            |
    //                            v
    //                          Term
    //                            |
    //                            v
    //                     TransactionCache
    //                        |        \
    //                        v          v
    // YOU ARE HERE -> CompoundTerm   4626Term

    /// Compound address
    ICompoundV3 public immutable yieldSource;

    /// Accumulates the inferred amount of invested shares of underlying by this contract
    uint256 internal yieldSharesIssued;

    /// @notice Associates the Compound contract to the protocol and sets
    ///         reserve limits
    /// @param _yieldSource Address of the Compound V3 implementation
    /// @param _linkerCodeHash The hash of the erc20 linker contract deploy code
    /// @param _factory The factory which is used to deploy the linking contracts
    /// @param _maxReserve Upper bound of underlying which can be held in the
    ///                    reserve
    /// @param _owner this address will be made owner
    /// @dev Also sets the targetReserve to be a half of the maxReserve.
    constructor(
        address _yieldSource,
        bytes32 _linkerCodeHash,
        address _factory,
        uint256 _maxReserve,
        address _owner
    )
        TransactionCacheTerm(
            _linkerCodeHash,
            _factory,
            _maxReserve,
            ICompoundV3(_yieldSource).baseToken(),
            _owner
        )
    {
        yieldSource = ICompoundV3(_yieldSource);
        token.approve(address(_yieldSource), type(uint256).max);
    }

    /// @notice Adds new funds to Compound and returns a share amount which
    ///         accounts for the interest from previous users.
    /// @param  amount The number of underlying to supply.
    /// @return shares The shares that have been produced by this deposit
    function _depositToYieldSource(uint256 amount)
        internal
        override
        returns (uint256 shares)
    {
        /// `accruedUnderlying` is the amount of underlying deposited and the
        /// interest accrued on those deposits
        uint256 accruedUnderlying = yieldSource.balanceOf(address(this));

        /// Deposits `underlying` into Compound
        yieldSource.supply(address(token), amount);

        /// Initial case where `shares` are valued 1:1 with underlying
        if (accruedUnderlying == 0) {
            yieldSharesIssued += amount;
            return (amount);
        }

        /// shares here represent "yieldShares" and "lockedShares".
        /// shares or "yieldShares" must be a constant representation of a
        /// growing amount of underlying. Compound accounts for yield in a
        /// rebasing mechanism and so we must infer to calculate claims of
        /// depositors for this system
        shares = (yieldSharesIssued * amount) / accruedUnderlying;

        /// Increments "yieldShares"
        yieldSharesIssued += shares;
    }

    /// @notice Withdraws the user from compound by calculating how much of the underlying and interest
    ///         that their percent of the held assets are. Sends the assets to a destination
    /// @param shares The number of yielding shares the user owns.
    /// @param dest The address to send the result of the withdraw to
    /// @return amount The underlying released by this withdraw
    function _withdrawFromYieldSource(uint256 shares, address dest)
        internal
        override
        returns (uint256 amount)
    {
        /// Calculates how much `underlying` the `_shares` are worth
        amount =
            (yieldSource.balanceOf(address(this)) * shares) /
            yieldSharesIssued;

        /// Withdraw `underlying` from Compound
        yieldSource.withdrawTo(dest, address(token), amount);

        /// Redeem back the `yieldShares`
        yieldSharesIssued -= shares;
    }

    /// @notice Converts from user shares to how many underlying they are worth on withdraw
    /// @param shares The shares which would be withdrawn
    /// @return amount The amount which would be produced by the withdraw.
    function _quoteWithdraw(uint256 shares)
        internal
        view
        override
        returns (uint256 amount)
    {
        amount =
            (yieldSource.balanceOf(address(this)) * shares) /
            yieldSharesIssued;
    }
}
