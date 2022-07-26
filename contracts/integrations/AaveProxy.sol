// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../Term.sol";
import "../libraries/Authorizable.sol";
import "../interfaces/IYieldAdapter.sol";
import "../interfaces/external/aave/IPool.sol";
import "../interfaces/external/aave/IRewardsController.sol";
import "../interfaces/external/aave/IAToken.sol";

contract AaveProxy is Term {
    // Aave contract addresses
    IPool public immutable pool;
    IRewardsController public immutable rewardsController;
    IAToken public immutable aToken;

    // these are stored as uint128's to be more gas efficient since
    // they are always accessed together
    // the proxy underlying reserve amount
    uint128 private _underlyingReserve;
    // the pool share amount
    uint128 private _atokenReserve;

    // the maximum amount of reserves for the proxy to store
    uint256 public immutable maxReserve;
    // the target minimum reserves for the proxy to store
    uint256 public immutable targetReserve;

    /// @notice constructs this contract
    /// @param _pool the aave pool
    /// @param _linkerCodeHash the hash of the erc20 linker contract
    /// @param _factory the factory which is used to deploy the linking contracts
    /// @param _token the underlying token
    /// @param _rewardsController the aave rewards controller
    /// @param _aToken the aave aToken
    /// @param _owner the contract owner who is authorized to collect rewards
    /// @param _maxReserve the proxy's max reserve amount
    constructor(
        address _pool,
        bytes32 _linkerCodeHash,
        address _factory,
        IERC20 _token,
        address _rewardsController,
        address _aToken,
        address _owner,
        uint256 _maxReserve
    ) Term(_linkerCodeHash, _factory, _token, _owner) {
        // Authorize the contract owner
        _authorize(_owner);

        pool = IPool(_pool);
        rewardsController = IRewardsController(_rewardsController);
        aToken = IAToken(_aToken);

        // set the reserve maximum and target
        maxReserve = _maxReserve;
        targetReserve = maxReserve / 2;

        // Set approval for the proxy
        token.approve(address(pool), type(uint256).max);
    }

    function underlyingReserve() public view returns (uint256) {
        return uint256(_underlyingReserve);
    }

    function aTokenReserve() public view returns (uint256) {
        return uint256(_atokenReserve);
    }

    /// @notice Deposits available funds into the Aave pool
    /// @param state the state of funds to deposit
    /// @return tuple (shares minted, amount underlying used)
    function _deposit(ShareState state)
        internal
        override
        returns (uint256, uint256)
    {
        // calls aave's supply
        return
            state == ShareState.Locked ? _depositLocked() : _depositUnlocked();
    }

    /// @notice The locked version of deposit
    /// @return tuple (shares minuted, amount underlying used)
    function _depositLocked() internal returns (uint256, uint256) {
        // load the contract's balance in underlying
        uint256 balance = token.balanceOf(address(this));
        // adjust the deposit amount by the underlying reserve
        uint256 depositAmount = balance - underlyingReserve();

        // load the balance of aTokens before depositing
        uint256 beforeBalance = aToken.balanceOf(address(this));

        // make the deposit into aave
        pool.supply(address(token), depositAmount, address(this), 0);

        // load the balance of aTokens after depositing
        uint256 afterBalance = aToken.balanceOf(address(this));

        // calculate the difference in aToken balances to know how many where created on deposit
        uint256 sharesMinted = afterBalance - beforeBalance;

        // return the shares created and the amount of underlying deposited into the pool
        return (sharesMinted, depositAmount);
    }

    // TODO: I think the math is going to be much different here because of the aTokens minted through pool's supply
    /// @notice The unlocked version of deposit
    /// @return tuple (shares minuted, amount underlying used)
    function _depositUnlocked() internal returns (uint256, uint256) {
        // get details about reserve state
        (
            uint256 underlyingReserve,
            uint256 aTokenReserve,
            uint256 aTokenReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();

        // load the contract's balance in underlying
        uint256 balance = token.balanceOf(address(this));
        // adjust the deposit amount by the underlying reserve
        uint256 depositAmount = balance - underlyingReserve;

        // calculate the shares deposited
        uint256 shares;
        if (impliedUnderlyingReserve == 0) {
            // if implied is zero, the shares deposited is equal to the deposit amount
            shares = depositAmount;
        } else {
            // else we adjust the share price
            shares =
                (depositAmount * totalSupply[UNLOCKED_YT_ID]) /
                impliedUnderlyingReserve;
        }

        // calculate the proposed reserves to see if they need to be adjusted
        uint256 proposedUnderlyingReserve = _underlyingReserve + depositAmount;
        if (proposedUnderlyingReserve > maxReserve) {
            // if the proposed amount is greater than the max reserve we deposit
            // the excess into the actual aave pool

            // load the balance of aTokens before depositing
            uint256 beforeBalance = aToken.balanceOf(address(this));
            pool.supply(
                address(token),
                proposedUnderlyingReserve - targetReserve,
                address(this),
                0
            );
            // load the balance of aTokens after depositing
            uint256 afterBalance = aToken.balanceOf(address(this));
            // set the new reserve amounts
            _setReserves(
                targetReserve,
                aTokenReserve + (afterBalance - beforeBalance)
            );
        } else {
            // if we haven't reached our max reserve, we don't deposit into the pool
            // set the new reserve amount
            _setReserves(proposedUnderlyingReserve, aTokenReserve);
        }

        return (shares, depositAmount);
    }

    /// @notice Turns unlocked shares into locked shares and vice versa
    /// @param state the status of the shares to convert
    /// @param amount the number of shares to convert
    /// @return the amount of shares that have been converted
    function _convert(ShareState state, uint256 amount)
        internal
        override
        returns (uint256)
    {
        return
            state == ShareState.Locked
                ? _convertLocked(amount)
                : _convertUnlocked(amount);
    }

    /// @notice converts shares from locked to unlocked
    /// @param lockedShares the number of locked shares to convert
    /// @return the amount of shares that have been converted
    function _convertLocked(uint256 lockedShares) internal returns (uint256) {
        // convert the shares to their underlying value
        uint256 amountToConvert = _convertToUnderlying(lockedShares);
        // get details about reserve state
        (
            uint256 underlyingReserve,
            uint256 aTokenReserve,
            uint256 aTokenReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();
        // adjust the value
        uint256 shares = (amountToConvert * totalSupply[UNLOCKED_YT_ID]) /
            impliedUnderlyingReserve;
        // increase the atoken reserve value
        _setReserves(underlyingReserve, aTokenReserve + lockedShares);
        return shares;
    }

    /// @notice converts shares from unlocked to locked
    /// @param unlockedShares the number of unlocked shares to convert
    /// @return the amount of shares that have been converted
    function _convertUnlocked(uint256 unlockedShares)
        internal
        returns (uint256)
    {
        // get details about reserve state
        (
            uint256 underlyingReserve,
            uint256 aTokenReserve,
            uint256 aTokenReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();
        // convert input shares to their underlying value
        // we have to account for amount already being burned from totalSupply
        uint256 amountToConvert = (unlockedShares * impliedUnderlyingReserve) /
            (unlockedShares + totalSupply[UNLOCKED_YT_ID]);

        // adjust reserve value
        _setReserves(underlyingReserve, aTokenReserve - unlockedShares);
        return amountToConvert;
    }

    /// @notice redeems shares from the pool and transfers to the user
    /// @param amount the number of shares to withdraw
    /// @param to the address to send the output funds
    /// @return the amount of funds freed from the redemption
    function _withdraw(
        uint256 amount,
        address to,
        ShareState state
    ) internal override returns (uint256) {
        // call's aave's withdraw
        return
            state == ShareState.Locked
                ? _withdrawLocked(amount, to)
                : _withdrawUnlocked(amount, to);
    }

    /// @notice the locked version of withdraw
    /// @param amount the number of shares to withdraw
    /// @param to the address to send the output funds
    /// @return the amount of funds freed from the redemption
    function _withdrawLocked(uint256 amount, address to)
        internal
        returns (uint256)
    {
        // convert the amount of shares to underlying to input to pools withdraw
        uint256 shares = _convertToUnderlying(amount);

        // execute the withdrawal (pool also transfers to the user)
        uint256 amountReceived = pool.withdraw(address(token), shares, to);

        return amountReceived;
    }

    /// @notice the unlocked version of withdraw
    /// @param amount the number of shares to withdraw
    /// @param to the address to send the output funds
    /// @return the amount of funds freed from the redemption
    function _withdrawUnlocked(uint256 amount, address to)
        internal
        returns (uint256)
    {
        // get details about reserve state
        (
            uint256 underlyingReserve,
            uint256 aTokenReserve,
            uint256 aTokenReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();
        // calculate the amount desired from the withdrawal
        uint256 underlyingDue = (amount * impliedUnderlyingReserve) /
            (amount + totalSupply[UNLOCKED_YT_ID]);

        if (underlyingDue <= underlyingReserve) {
            // if the desired amount is within the proxy's underlying reserves
            // then withdraw from those instead of the actual pool

            // set new reserve amount
            _setReserves(underlyingReserve - underlyingDue, aTokenReserve);
            // transfer from the proxy to the user
            token.transferFrom(address(this), to, underlyingDue);
        } else {
            if (underlyingDue <= aTokenReserveAsUnderlying) {
                // if the desired amount is within the aToken reserve we withdraw from
                // the pool to the proxy
                uint256 amountReceived = pool.withdraw(
                    address(token),
                    underlyingDue,
                    address(this)
                );
                // transfer the amount due to the user
                token.transfer(to, underlyingDue);
                // adjust the reserve amount
                _setReserves(underlyingReserve, aTokenReserve - amountReceived);
            } else {
                // the desired amount is greater than either reserve type
                // so we withdraw from a combination of them

                // withdraw the entire amount from the aToken reserve
                uint256 amountReceived = pool.withdraw(
                    address(token),
                    aTokenReserve,
                    to
                );
                // adjust the reserve value to take the remaining withdraw amount underlying reserve
                _setReserves(
                    underlyingReserve - (underlyingDue - amountReceived),
                    0
                );
            }
        }
        return underlyingDue;
    }

    /// @notice Get the underlying amount of tokens per shares given
    /// @param amount The amount of shares you want to know the value of
    /// @param state the status of the shares
    /// @return the amount of underlying the input is worth
    function _underlying(uint256 amount, ShareState state)
        internal
        view
        override
        returns (uint256)
    {
        return 0;
    }

    /// @notice claim Aave rewards for a user
    /// @param to the address to send the rewards to
    function collectRewards(address to) external onlyAuthorized {
        // create an address array for input of claim function
        address[] memory aTokenAddress = new address[](1);
        aTokenAddress[0] = address(aToken);
        // claim rewards and transfer to the user
        rewardsController.claimAllRewards(aTokenAddress, to);
    }

    /// @notice placeholder function for conversion math TBD
    // in 4626 vaults, previewRedeem is a handy way to do this that Aave does not have
    function _convertToUnderlying(uint256 amount)
        internal
        pure
        returns (uint256)
    {
        return 0;
    }

    function reserveDetails()
        public
        view
        returns (
            uint256 underlyingReserve,
            uint256 aTokenReserve,
            uint256 aTokenReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        )
    {
        (underlyingReserve, aTokenReserve) = (
            uint256(_underlyingReserve),
            uint256(_atokenReserve)
        );

        aTokenReserveAsUnderlying = _convertToUnderlying(_atokenReserve);

        impliedUnderlyingReserve = (underlyingReserve +
            aTokenReserveAsUnderlying);
    }

    function _setReserves(
        uint256 _newUnderlyingReserve,
        uint256 _newVaultShareReserve
    ) internal {
        _underlyingReserve = uint128(_newUnderlyingReserve);
        _atokenReserve = uint128(_newVaultShareReserve);
    }
}
