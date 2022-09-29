// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "./Term.sol";

// This contract is an abstraction called a gas reserve where a yield source be deposited on withdraw
// from with lower gas by allowing execution against reserve.

// Inheritance Map -
//
//     Multi-token
//         |
//         v
//        Term
//         |
//         v
//       GasReserve      <- YOU ARE HERE
//       |        \
//       v          v
//  CompoundTerm   4626Term

/// ### ShareState.Locked ###

/// "shares" in this context are congruent with "vaultShares". Simply,
/// we can price "shares" the same as "vaultShares" relative to their claim on
/// underlying in the ERC4626 vault. An important point is that depositing and
/// withdrawing at the start and end of a given term garners no loss of yield
/// relative to dealing with the ERC4626 vault directly.

/// ### ShareState.Unlocked ###

/// "shares" here differ from the "Locked" context so that the protocol can
/// implement a gas reserve for an improved LP experience for small users and an
/// overall more performative position for all LPers than version 1 of the
/// Element Protocol by comparison.
/// In context of the wider architecture outside of this contract, the "shares"
/// here represent a perpetual claim on a capped reserve of underlying withheld
/// in the contract and underlying deposits generating yield in the ERC4626
/// vault. This means that because the total sum of underlying is not deposited
/// into the ERC4626 vault, by comparison with ShareState.Locked, there will
/// be marginally less yield accrued throughout the duration of a term and price
/// "unlocked" shares marginally worse than the equivalent "locked" shares.
/// The tradeoff for having this reserve of underlying withheld from being
/// deposited and accruing yield is so that smaller users can cheaply enter
/// and exit LP positions by depositing and withdrawing underlying to and from
/// the reserve instead of directly depositing to the ERC4626 vault.

abstract contract GasReserveTerm is Term {
    /// accounts for the balance of "unlocked" underlying for this term
    uint128 internal _underlyingReserve;

    /// accounts for the balance of "unlocked" vaultShares for this term
    uint128 internal _yieldShareReserve;

    /// upper limit of balance of _underlyingReserve allowed in this contract
    uint256 public immutable maxReserve;

    /// desired amount of underlying
    uint256 public immutable targetReserve;

    /// @notice Constructs this function
    /// @param _linkerCodeHash The hash of the erc20 linker contract deploy code
    /// @param _factory The factory which is used to deploy the linking contracts
    /// @param _maxReserve Upper bound of underlying which can be held in the
    ///                    reserve
    /// @param _token The address of the underlying token for this yield source
    /// @param _owner this address will be made owner
    constructor(
        bytes32 _linkerCodeHash,
        address _factory,
        uint256 _maxReserve,
        address _token,
        address _owner
    ) Term(_linkerCodeHash, _factory, IERC20(_token), _owner) {
        maxReserve = _maxReserve;
        targetReserve = _maxReserve / 2;
    }

    /// Abstract functions

    /// The following functions must be implemented for the yield source in an inheriting contract
    /// before this gets deployed.

    // Takes an amount of tokens which must be held in the balance of the contract and deposits them
    // into the external yield source
    function _depositToYieldSource(uint256 amount)
        internal
        virtual
        returns (uint256 shares);

    // Takes in the number of yielding shares and then withdraws them from the external source
    function _withdrawFromYieldSource(uint256 shares, address dest)
        internal
        virtual
        returns (uint256 amount);

    // Quotes a withdraw from yielding shares
    function _quoteWithdraw(uint256 shares)
        internal
        view
        virtual
        returns (uint256 amount);

    /// Implementation functions

    /// The following functions implement the abstract functions from the term contract

    /// @notice Deposits underlying into the ERC4626 vault and issues shares
    /// @param _state The context designation of the resulting shares
    /// @return Returns a tuple of number of shares and the value of those
    ///         shares in underlying
    function _deposit(ShareState _state)
        internal
        override
        returns (uint256, uint256)
    {
        return
            _state == ShareState.Locked ? _depositLocked() : _depositUnlocked();
    }

    /// @notice Deposits underlying directly into the vault and issues "shares"
    ///         1:1 with the amount of vaultShares returned
    /// @return shares Amount of shares issued
    /// @return underlying Underlying value of shares issued
    function _depositLocked()
        internal
        returns (uint256 shares, uint256 underlying)
    {
        /// Underlying is calculated by getting the differential balance of the
        /// contract and the reserve of underlying.
        underlying =
            token.balanceOf(address(this)) -
            uint256(_underlyingReserve);

        /// deposits directly into the vault
        shares = _depositToYieldSource(underlying);
    }

    /// @notice Deposits underlying either directly into the `underlyingReserve`
    ///         or does a rebalancing of the `underlyingReserve` into the
    ///         `vaultShareReserve`.
    /// @return shares Amount of shares issued
    /// @return underlying Underlying value of shares issued
    function _depositUnlocked()
        internal
        returns (uint256 shares, uint256 underlying)
    {
        /// See reserveDetails()
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            ,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        /// Underlying is calculated by getting the differential balance of the
        /// contract and the reserve of underlying.
        underlying = token.balanceOf(address(this)) - underlyingReserve;

        /// Shares in the "Unlocked" context are a claim on the underlying in
        /// the `underlyingReserve` and the redeemable value in underlying of
        /// the `vaultShareReserve`
        if (totalSupply[UNLOCKED_YT_ID] == 0) {
            /// This is primarily the initial case and implies that the
            /// `underlyingReserve` and `vaultShareReserve` are 0. Therefore
            /// `shares` are issued 1:1 with the amount of `underlying`
            shares = underlying;
        } else {
            /// In the general case, we can price `shares` relative to the ratio
            /// of total issued shares to the `underlyingReserve` + underlying
            /// value of the `vaultShareReserve`
            /// Note - when totalSupply of the unlocked token is not zero we expect
            ///        that the 'impliedUnderlyingReserve' != 0
            shares =
                (underlying * totalSupply[UNLOCKED_YT_ID]) /
                impliedUnderlyingReserve;
        }

        /// Precomputed sum of `underlyingReserve` and deposited `underlying`
        uint256 proposedUnderlyingReserve = underlyingReserve + underlying;

        /// Accounting of the reserves when depositing works as follows:

        /// - When the sum of the `underlyingReserve` and deposited `underlying`
        /// exceeds the maxReserve limit a rebalancing must occur, swapping
        /// all but a `targetReserve` amount of `underlying` for `vaultShares`.

        /// - The case where the `maxReserve` limit is not exceeded, no deposit to
        /// the external yield source occurs

        /// We can expect across multiple consecutive deposits through either
        /// of these code paths that the reserve of underlying to float between
        /// `targetReserve` and `maxReserve` while the reserve of `vaultShares`
        /// should increase over time
        if (proposedUnderlyingReserve > maxReserve) {
            /// Deposits all underlying in the contract less a `targetReserve`
            /// amount, returning an amount of yielding shares
            uint256 vaultShares = _depositToYieldSource(
                proposedUnderlyingReserve - targetReserve
            );

            /// Sets the `underlyingReserve` to `targetReserve` amount
            /// and increments the amount of vaultShares in the
            /// `vaultShareReserve` with the amount of vaultShares returned
            /// from the deposit
            _setReserves(targetReserve, vaultShareReserve + vaultShares);
        } else {
            /// We set the `underlyingReserve` to the precomputed sum of
            /// underlying deposited and existing `underlyingReserve`. The
            /// `vaultShare` reserve is unchanged
            _setReserves(proposedUnderlyingReserve, vaultShareReserve);
        }
    }

    /// @notice Withdraws underlying from the ERC4626 vault by redeeming shares
    /// @param _shares Amount of "shares" user will redeem for underlying
    /// @param _dest Address underlying will be sent to
    /// @param _state The context designation of the shares
    /// @return Returns the amount of underlying redeemed for amount of shares
    function _withdraw(
        uint256 _shares,
        address _dest,
        ShareState _state
    ) internal override returns (uint256) {
        return
            _state == ShareState.Locked
                ? _withdrawLocked(_shares, _dest)
                : _withdrawUnlocked(_shares, _dest);
    }

    /// @notice Withdraws underlying directly from the ERC4626 vault using
    ///         "shares" which are directly proportional to "vaultShares"
    /// @param _shares Amount of "shares" user will redeem for underlying
    /// @param _dest Address underlying will be sent to
    /// @return underlying Returns the amount of underlying redeemed for amount
    ///         of shares
    function _withdrawLocked(uint256 _shares, address _dest)
        internal
        returns (uint256 underlying)
    {
        /// Redeems `_vaultShares` for underlying
        underlying = _withdrawFromYieldSource(_shares, _dest);
    }

    /// @notice Withdraws an amount of underlying from either the
    ///         `underlyingReserve` or by redeeming a portion of the
    ///         `vaultShareReserve` for more underlying
    /// @param _shares Amount of "shares" user will redeem for underlying
    /// @param _dest Address underlying will be sent to
    /// @return underlying Returns the amount of underlying redeemed for amount
    ///         of shares
    function _withdrawUnlocked(uint256 _shares, address _dest)
        internal
        returns (uint256 underlying)
    {
        /// See reserveDetails()
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        /// Underlying due to the user is calculated relative to the ratio of
        /// the `underlyingReserve` + underlyingValue of the `vaultShareReserve`
        /// and the total supply of shares issued.

        /// NOTE: There is an accounting caveat here as the `_shares` amount has
        /// been previously burned from the shares totalSupply. This must be
        /// accounted for so shares are redeemed in the correct ratio
        underlying =
            (_shares * impliedUnderlyingReserve) /
            (_shares + totalSupply[UNLOCKED_YT_ID]);

        /// Accounting of the reserves when withdrawing works as follows:

        /// 1) When the underlying due to the user is less than or equal to
        /// `underlyingReserve`, that amount is transferred directly from the
        /// reserve to the user.

        /// 2) If the amount of underlying due to the user is greater than the
        /// underlyingReserve, the logic breaks into two further cases:
        ///   2.1) If the amount of underlying due is greater than the
        ///        underlying value of the `vaultShareReserve`, the entire
        ///        `vaultShareReserve` is redeemed directly from the ERC4626
        ///        vault for an amount of underlying, effectively removing all
        ///        underlying from accruing yield.
        ///        The underlying due to the user is then taken from the sum of
        ///        underlying redeemed from the `vaultShareReserve` and the
        ///        `underlyingReserve`
        ///   2.2) If the amount of underlying due is less than or equal to
        ///        the underlying value of the `vaultShareReserve`, the
        ///        underlying due is withdrawn directly from the ERC4626 vault
        ///        removing `vaultShares` from the `vaultShareReserve`. The
        ///        underlyingReserve in this instance is left untouched
        if (underlying <= underlyingReserve) {
            /// Deducts amount of underlying due from `underlyingReserve`
            _setReserves(underlyingReserve - underlying, vaultShareReserve);

            /// Transfers underlying due to `_dest`
            token.transfer(_dest, underlying);
        } else {
            /// Check if underlying value of vaultShareReserve can cover the
            /// amount of underlying due to the user
            if (underlying > vaultShareReserveAsUnderlying) {
                /// Redeem all of the `vaultShareReserve` for an amount of
                /// underlying
                uint256 underlyingRedeemed = _withdrawFromYieldSource(
                    vaultShareReserve,
                    address(this)
                );

                /// Transfer underlying due to `_dest`
                token.transfer(_dest, underlying);
                /// As we have checked implicitly `underlying` is greater than
                /// `underlyingRedeemed`, it is assumed that the
                /// `vaultShareReserve` is empty and any remaining underlying
                /// due is covered by the `underlyingReserve`.
                _setReserves(
                    underlyingReserve - (underlying - underlyingRedeemed),
                    0
                );
            } else {
                // We calculate the price per share as (vaultShareReserveAsUnderlying/vaultShareReserve)
                // This lets us calculate the shares to withdraw to get underlying needed by dividing by
                // pricePerShare. We simplify to work with fixed decimals better
                uint256 yieldSharesToWithdraw = (underlying *
                    vaultShareReserve) / vaultShareReserveAsUnderlying;
                // Directly withdraws the shares needed to cover the underlying value from the yield source
                // and sends the tokens to the destination
                uint256 vaultShares = _withdrawFromYieldSource(
                    yieldSharesToWithdraw,
                    _dest
                );
                /// The `underlyingReserve` is unchanged. Deducts `vaultShares`
                /// burned from the withdrawal from the `vaultShareReserve`
                _setReserves(
                    underlyingReserve,
                    vaultShareReserve - yieldSharesToWithdraw
                );
            }
        }
    }

    /// @notice Converts shares between respective "ShareStates", exchanging
    ///         by accounting internally how much underlying both are worth
    /// @param _state The ShareState the shares will be converted from
    /// @param _shares Amount of "shares" user will redeem for underlying
    /// @return Amount of "shares" of the opposite ShareState which is
    ///         exchanged for
    function _convert(ShareState _state, uint256 _shares)
        internal
        override
        returns (uint256)
    {
        return
            _state == ShareState.Locked
                ? _convertLocked(_shares)
                : _convertUnlocked(_shares);
    }

    /// @notice Converts "locked" shares into "unlocked" shares
    /// @param _lockedShares Amount of "locked" shares to be exchanged
    /// @return unlockedShares Amount of "unlocked" shares exchanged for
    function _convertLocked(uint256 _lockedShares)
        internal
        returns (uint256 unlockedShares)
    {
        /// See reserveDetails()
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        /// Get the underlying value of the amount of "locked" shares
        /// vaultShareReserveAsUnderlying/vaultShareReserve = pricePerShare
        uint256 lockedSharesAsUnderlying = (_lockedShares *
            vaultShareReserveAsUnderlying) / vaultShareReserve;

        /// Computes the value of "unlocked" shares for the underlying value of
        /// the "locked" shares
        unlockedShares =
            (lockedSharesAsUnderlying * totalSupply[UNLOCKED_YT_ID]) /
            impliedUnderlyingReserve; // NOTE: zero divide here if reserves are not initialized

        /// The `vaultShares` representing the "locked" shares already exist on
        /// the contract so the `vaultShareReserve` is incremented with the
        /// amount of `_lockedShares`
        _setReserves(underlyingReserve, vaultShareReserve + _lockedShares);
    }

    /// @notice Converts "unlocked" shares into "locked" shares
    /// @param _unlockedShares Amount of "unlocked" shares which will be exchanged
    /// @return lockedShares Amount of "locked" shares exchanged for
    function _convertUnlocked(uint256 _unlockedShares)
        internal
        returns (uint256 lockedShares)
    {
        /// See reserveDetails()
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        /// NOTE: There is an accounting caveat here as the `_unlockedShares`
        /// amount has been previously burned from the shares totalSupply. This
        /// must be accounted for so shares are redeemed in the correct ratio
        uint256 unlockedSharesAsUnderlying = (_unlockedShares *
            impliedUnderlyingReserve) /
            (_unlockedShares + totalSupply[UNLOCKED_YT_ID]);

        /// Compute the value of "locked" shares using the underlying value of
        /// the "unlocked" shares. We do this by dividing by pricePerShare
        /// Note: implicitly, vaultShareReserveAsUnderlying/vaultShareReserve = pricePerShare
        lockedShares =
            (unlockedSharesAsUnderlying * vaultShareReserve) /
            vaultShareReserveAsUnderlying;

        /// Check if enough `vaultShares` in the `vaultShareReserve`
        /// Note - while we don't allow converts in this code path withdraws are still possible.
        ///        this may cause errors in the buy YT flow if the AMM is traded to a point where
        ///        the users trade would require the AMM to make PTs from the gas reserve.
        if (lockedShares > vaultShareReserve)
            revert ElementError.VaultShareReserveTooLow();

        /// Deduct `lockedShares` from the `vaultShareReserve`
        _setReserves(underlyingReserve, vaultShareReserve - lockedShares);
    }

    /// @notice Calculates the underlying value of the shares in either
    ///         ShareState
    /// @param _shares Amount of "shares" to be valued
    /// @param _state The "ShareState" of the `_shares`
    /// @return The underlying value of `_shares`
    function _underlying(uint256 _shares, ShareState _state)
        internal
        view
        override
        returns (uint256)
    {
        /// When pricing "locked" shares, `_shares` are directly analogous to
        /// `vaultShares` and so we can price them as if they were

        /// In the "unlocked" context, `_shares` are priced relative to the ratio
        /// of the `impliedUnderlying` and the totalSupply of "unlocked" shares
        if (_state == ShareState.Locked) {
            return _quoteWithdraw(_shares);
        } else {
            (, , , uint256 impliedUnderlyingReserve) = reserveDetails();
            return
                (_shares * impliedUnderlyingReserve) /
                totalSupply[UNLOCKED_YT_ID];
        }
    }

    /// @notice Helper function for retrieving information about the reserves
    /// @return underlyingReserve The amount of underlying accounted for in
    ///         `_underlyingReserve`
    /// @return vaultShareReserve The amount of vaultShares accounted for in
    ///         `_yieldShareReserve`
    /// @return vaultShareReserveAsUnderlying The underlying value of the
    ///         vaultShareReserve
    /// @return impliedUnderlyingReserve The sum of the `underlyingReserve`
    ///         and the underlying value of the `vaultShareReserve`. The total
    ///         "unlocked" shares are a proportional claim on this amount of
    ///         underlying
    function reserveDetails()
        public
        view
        returns (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        )
    {
        /// Retrieve both reserves.
        (underlyingReserve, vaultShareReserve) = (
            uint256(_underlyingReserve),
            uint256(_yieldShareReserve)
        );

        /// Compute the underlying value of the `vaultShareReserve`
        vaultShareReserveAsUnderlying = _quoteWithdraw(vaultShareReserve);

        /// Compute the implied underlying value of both reserves
        impliedUnderlyingReserve = (underlyingReserve +
            vaultShareReserveAsUnderlying);
    }

    /// @notice Setter function which overwrites the reserve values
    /// @param _newUnderlyingReserve the new underlyingReserve amount
    /// @param _newVaultShareReserve the new vaultShareReserve amount
    function _setReserves(
        uint256 _newUnderlyingReserve,
        uint256 _newVaultShareReserve
    ) internal {
        _underlyingReserve = uint128(_newUnderlyingReserve);
        _yieldShareReserve = uint128(_newVaultShareReserve);
    }
}
