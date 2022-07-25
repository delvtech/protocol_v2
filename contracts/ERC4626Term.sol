// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "./Term.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IERC20.sol";
import "./MultiToken.sol";

/// @title Term contract instance for the EIP-4626 Tokenized Vault Standard
///
/// @notice ERC4626Term is an implementation of the IYieldAdapter which is used
/// to interface the Element Protocol with yield bearing positions which utilise the
/// EIP-4626 Tokenized Vault Standard.
///
/// @dev ERC4626Term implements an interface for the EIP-4626 Tokenized Vault
/// Standard. The contract is used internally by instances of Term.sol to `deposit`/`withdraw`
/// a users amount of underlying for/from "shares" which are used by the Element Protocol to derive
/// Principal and Yield Tokens.
/// The definition of "shares" is significant as it has two implied meanings and understanding them
/// is important in understanding the architecture of the protocol.
///
/// NOTE: To disambiguate ERC4626's conception of "shares" and the Element
/// Protocol's version, ERC4626's "shares" have been renamed here as "vaultShares"
///
/// ### ShareState.Locked ###
///
/// "shares" in this context are congruent with "vaultShares". Simply,
/// we can price "shares" the same as "vaultShares" relative to their claim on
/// underlying in the ERC4626 vault. An important point is that depositing and
/// withdrawing at the start and end of a given term garners no loss of yield
/// relative to dealing with the ERC4626 vault directly.
///
/// ### ShareState.Unlocked ###
///
/// "shares" here differ from the "Locked" context so that the protocol can
/// implement a gas reserve for an improved LP experience for small users and an
/// overall more performative position for all LPers than protocol V1. In
/// context of the wider architecture outside of this contract, the "shares"
/// are a perpetual claim on a reserve of underlying withheld in the contract
/// and underlying generating yield in the ERC4626 vault. This will price "
/// shares" differently and will be less performative than the equivalent
/// "Locked" shares over the duration of a term.
/// The tradeoff for this decrease in performance is that small users can
/// directly deposit and withdraw into and from the underlying reserve without
/// having to interact with the ERC4626 vault, making LPing more gas efficient.
/// Also, in comparison to the AMM architecture of V1 of the protocol, 50% of
/// LPers underlying had to be used for market-making and could not be fully
/// utilised to generate yield. By introducing an internally accountable
/// adjusted abstraction over the yield position, LPers can utilise almost all
/// of their capital while market making.
///
contract ERC4626Term is Term {
    // address of ERC4626 vault
    IERC4626 public immutable vault;

    // accounts for the balance of "unlocked" underlying for this term
    uint128 private _underlyingReserve;
    // accounts for the balance of "unlocked" vaultShares for this term
    uint128 private _vaultShareReserve;

    // upper limit of balance of _underlyingReserve allowed in this contract
    uint256 public immutable maxReserve;
    // desired amount of underlying
    uint256 public immutable targetReserve;

    /// @notice Associates the vault to the protocol and sets reserve limits
    /// @param _vault Address of the ERC4626 vault
    /// @param _linkerCodeHash The hash of the erc20 linker contract deploy code
    /// @param _factory The factory which is used to deploy the linking contracts
    /// @param _maxReserve Upper bound of underlying which can be held in the
    ///                    reserve
    /// @dev Also sets the targetReserve to be a half of the maxReserve.
    constructor(
        IERC4626 _vault,
        bytes32 _linkerCodeHash,
        address _factory,
        uint256 _maxReserve
    ) Term(_linkerCodeHash, _factory, IERC20(_vault.asset())) {
        vault = _vault;
        maxReserve = _maxReserve;
        targetReserve = _maxReserve / 2;
        token.approve(address(_vault), type(uint256).max);
    }

    /// @notice Amount of underlying held in reserve for the "Unlocked" context
    /// @return Returns the number of underlying held in the `_underlyingReserve`
    function underlyingReserve() public view returns (uint256) {
        return uint256(_underlyingReserve);
    }

    /// @notice Amount of vaultShares held in reserve in the contract. This
    ///         is only representative of the amount of vaultShares held in the
    ///         "Unlocked" context.
    /// @return Returns the number of vaultShares held in the `_vaultShareReserve`
    function vaultShareReserve() public view returns (uint256) {
        return uint256(_vaultShareReserve);
    }

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
    /// @return Returns a tuple of number of shares and the value of those
    ///         shares in underlying
    function _depositLocked()
        internal
        returns (uint256 shares, uint256 underlying)
    {
        /// underlying is calculated by getting the differential balance of the
        /// contract and the reserve of underlying.
        underlying = token.balanceOf(address(this)) - underlyingReserve();

        /// deposits directly into the vault
        shares = vault.deposit(underlying, address(this));
    }

    /// @notice Deposits underlying into the mutated reserve + vault position
    /// @return Returns a tuple of number of shares and the value of those
    ///         shares in underlying
    function _depositUnlocked()
        internal
        returns (uint256 shares, uint256 underlying)
    {
        /// See reserveDetails()
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        /// underlying is calculated by getting the differential balance of the
        /// contract and the reserve of underlying.
        underlying = token.balanceOf(address(this)) - underlyingReserve;

        /// Shares in the "Unlocked" context are a claim on the underlying in
        /// the `underlyingReserve` and the redeemable value in underlying of
        /// the `vaultShareReserve`
        if (impliedUnderlyingReserve == 0) {
            /// This is primarily the initial case and implies that the
            /// `underlyingReserve` and `vaultShareReserve` are 0. Therefore
            /// `shares` are issued 1:1 with the amount of `underlying`
            shares = underlying;
        } else {
            /// In the general case, we can price `shares` relative to the ratio
            /// of total issued shares to the `underlyingReserve` + underlying
            /// value of the `vaultShareReserve`
            shares =
                (underlying * totalSupply[UNLOCKED_YT_ID]) /
                impliedUnderlyingReserve;
        }

        /// Precomputed sum of `underlyingReserve` and deposited `underlying`
        uint256 proposedUnderlyingReserve = underlyingReserve + underlying;

        // If sum total of underlying exceeds the maxReserve we rebalance to the
        // targetReserve.

        /// Accounting of the reserves when depositing works as follows:
        ///
        /// - When the sum of the `underlyingReserve` and deposited `underlying`
        /// exceeds the maxReserve limit a rebalancing must occur, swapping
        /// all but a `targetReserve` amount of `underlying` for `vaultShares`.
        ///
        /// - The case where the `maxReserve` limit is not exceeded, no deposit to
        /// the ERC4626 vault occurs.
        ///
        /// We can expect across multiple consecutive deposits through either
        /// of these code paths that the reserve of underlying to float between
        /// `targetReserve` and `maxReserve` while the reserve of `vaultShares`
        /// should increase over time
        if (proposedUnderlyingReserve > maxReserve) {
            /// Deposits all underlying in the contract less a `targetReserve`
            /// amount, returning an amount of vaultShares
            uint256 vaultShares = vault.deposit(
                proposedUnderlyingReserve - targetReserve,
                address(this)
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

    function _withdrawLocked(uint256 _vaultShares, address _dest)
        internal
        returns (uint256)
    {
        return vault.redeem(_vaultShares, _dest, address(this));
    }

    function _withdrawUnlocked(uint256 _shares, address _dest)
        internal
        returns (uint256)
    {
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        // NOTE: Shares MUST be burnt/removed from accounting for term before
        // calling withdraw unlocked.
        uint256 underlyingDue = (_shares * impliedUnderlyingReserve) /
            (_shares + totalSupply[UNLOCKED_YT_ID]);

        if (underlyingDue <= underlyingReserve) {
            _setReserves(underlyingReserve - underlyingDue, vaultShareReserve);
            token.transfer(_dest, underlyingDue);
        } else {
            if (underlyingDue > vaultShareReserveAsUnderlying) {
                uint256 underlyingRedeemed = vault.redeem(
                    vaultShareReserve,
                    address(this),
                    address(this)
                );

                token.transfer(_dest, underlyingDue);
                _setReserves(
                    underlyingReserve - (underlyingDue - underlyingRedeemed),
                    0
                );
            } else {
                uint256 withdrawnVaultShares = vault.withdraw(
                    underlyingDue,
                    _dest,
                    address(this)
                );
                _setReserves(
                    underlyingReserve,
                    vaultShareReserve - withdrawnVaultShares
                );
            }
        }
        return underlyingDue;
    }

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

    function _convertLocked(uint256 _vaultShares)
        internal
        returns (uint256 shares)
    {
        uint256 vaultSharesAsUnderlying = vault.previewRedeem(_vaultShares);
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            ,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        shares =
            (vaultSharesAsUnderlying * totalSupply[UNLOCKED_YT_ID]) /
            impliedUnderlyingReserve; // NOTE: zero divide here if reserves are not initialised

        _setReserves(underlyingReserve, vaultShareReserve + _vaultShares);
    }

    function _convertUnlocked(uint256 _shares)
        internal
        returns (uint256 vaultShares)
    {
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            ,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        // NOTE: Shares MUST be burnt/removed from accounting for term before
        // calling convert unlocked.
        uint256 sharesAsUnderlying = (_shares * impliedUnderlyingReserve) /
            (_shares + totalSupply[UNLOCKED_YT_ID]);

        vaultShares = vault.previewWithdraw(sharesAsUnderlying);

        require(vaultShares <= vaultShareReserve, "not enough vault shares");

        _setReserves(underlyingReserve, vaultShareReserve - vaultShares);
    }

    function _underlying(uint256 _shares, ShareState _state)
        internal
        view
        override
        returns (uint256)
    {
        if (_state == ShareState.Locked) {
            return vault.previewRedeem(_shares);
        } else {
            (, , , uint256 impliedUnderlyingReserve) = reserveDetails();
            return
                (_shares * impliedUnderlyingReserve) /
                totalSupply[UNLOCKED_YT_ID];
        }
    }

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
        (underlyingReserve, vaultShareReserve) = (
            uint256(_underlyingReserve),
            uint256(_vaultShareReserve)
        );

        vaultShareReserveAsUnderlying = vault.previewRedeem(vaultShareReserve);

        impliedUnderlyingReserve = (underlyingReserve +
            vaultShareReserveAsUnderlying);
    }

    function _setReserves(
        uint256 _newUnderlyingReserve,
        uint256 _newVaultShareReserve
    ) internal {
        _underlyingReserve = uint128(_newUnderlyingReserve);
        _vaultShareReserve = uint128(_newVaultShareReserve);
    }
}
