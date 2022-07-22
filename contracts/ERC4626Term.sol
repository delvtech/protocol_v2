// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.15;

import "./Term.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IERC20.sol";
import "./MultiToken.sol";

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
        //token.approve(address(this), type(uint256).max);
    }

    function underlyingReserve() public view returns (uint256) {
        return uint256(_underlyingReserve);
    }

    function vaultShareReserve() public view returns (uint256) {
        return uint256(_vaultShareReserve);
    }

    // @notice Deposits underlying into yield source and issues shares
    // @param _state The context in which the shares for this term are categorised for
    function _deposit(ShareState _state)
        internal
        override
        returns (uint256, uint256)
    {
        return
            _state == ShareState.Locked ? _depositLocked() : _depositUnlocked();
    }

    function _depositLocked()
        internal
        returns (uint256 shares, uint256 underlyingDeposited)
    {
        // We derive the underlyingDeposited by the user by getting the
        // difference of the underlyingReserve and the current underlying
        // balance of the contract
        underlyingDeposited =
            token.balanceOf(address(this)) -
            underlyingReserve();

        // In a Locked ShareState, shares are issued proportionally to the
        // amount of vaultShares issued for the underlying deposited. In this
        // context we say that shares and vaultShares are equal and
        // interchangeable
        shares = vault.deposit(underlyingDeposited, address(this));
    }

    function _depositUnlocked()
        internal
        returns (uint256 shares, uint256 underlyingDeposited)
    {
        // See reserveDetails()
        (
            uint256 underlyingReserve,
            uint256 vaultShareReserve,
            uint256 vaultShareReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        // We derive the underlyingDeposited by the user by getting the
        // difference of the underlyingReserve and the current underlying
        // balance of the contract
        underlyingDeposited =
            token.balanceOf(address(this)) -
            underlyingReserve;

        // In an Unlocked ShareState, shares are issued proportionally to the
        // impliedUnderlyingReserve which is a derived value representing the
        // sum of the underlyingReserve and the underlying value of the
        // vaultShareReserve.
        //
        // If the impliedUnderlyingReserve is 0, shares are issued directly 1:1
        // as the initial case would not have any accrued interest causing a
        // divergence in the ratio of shares:impliedUnderlying
        if (impliedUnderlyingReserve == 0) {
            shares = underlyingDeposited;
        } else {
            // In the more general case, we compute the amount of shares for
            // underlyingDeposited by the ratio of total unlocked shares and
            // the amount of impliedUnderlying across the two reserves
            shares =
                (underlyingDeposited * totalSupply[UNLOCKED_YT_ID]) /
                impliedUnderlyingReserve;
        }

        // Calculate the sum total of underlying in the contract
        uint256 proposedUnderlyingReserve = underlyingReserve +
            underlyingDeposited;

        // If sum total of underlying exceeds the maxReserve we rebalance to the
        // targetReserve.
        if (proposedUnderlyingReserve > maxReserve) {
            // When maxReserve is exceeded, the sum total of underlying on the
            // contract less the targetReserve amount is deposited giving an
            // amount of vaultShares
            uint256 vaultShares = vault.deposit(
                proposedUnderlyingReserve - targetReserve,
                address(this)
            );

            // We reset the accounting for both reserves adding the newly issued
            // vaultShares to the vaultShareReserve and setting the
            // underlyingReserve to the targetReserve
            _setReserves(targetReserve, vaultShareReserve + vaultShares);
        } else {
            // This is the more gas efficient path where if the user is
            // depositing an amount of underlying that causes the
            // underlyingReserve to not exceed the maxReserve than we delay
            // that deposit until a future depositor exceeds the limit. The user
            // is still issued shares proportional
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
