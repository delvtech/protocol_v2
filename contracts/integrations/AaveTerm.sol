// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../Term.sol";
import "../libraries/Authorizable.sol";
import "../interfaces/IYieldAdapter.sol";
import "../interfaces/external/aave/IPool.sol";
import "../interfaces/external/aave/IRewardsController.sol";
import "../interfaces/external/aave/IAToken.sol";

contract AaveTerm is Term {
    // Aave contract addresses
    IPool public immutable pool;
    IRewardsController public immutable rewardsController;
    IAToken public immutable aToken;

    // these are stored as uint128's to be more gas efficient since
    // they are always accessed together
    // the term's underlying reserve amount
    uint128 private _underlyingReserve;
    // the pool share amount
    uint128 private _aTokenReserve;

    // the maximum amount of reserves for the term contract to store
    uint256 public immutable maxReserve;
    // the target minimum reserves for the term contract to store
    uint256 public immutable targetReserve;

    // TODO: don't like the name of this, ideas: suppliedValue, depositedValue
    // the amount of shares deposited into the pool
    uint256 private _depositedATokens;

    /// @notice constructs this contract
    /// @param _pool the aave pool
    /// @param _linkerCodeHash the hash of the erc20 linker contract
    /// @param _factory the factory which is used to deploy the linking contracts
    /// @param _token the underlying token
    /// @param _rewardsController the aave rewards controller
    /// @param _aToken the aave aToken
    /// @param _owner the contract owner who is authorized to collect rewards
    /// @param _maxReserve the term's max reserve amount
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

        // Set approval for the aave term
        token.approve(address(pool), type(uint256).max);
    }

    function underlyingReserve() public view returns (uint256) {
        return uint256(_underlyingReserve);
    }

    function aTokenReserve() public view returns (uint256) {
        return uint256(_aTokenReserve);
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

        // supply the pool and get the shares minted
        uint256 sharesMinted = _supplyAavePool(depositAmount);

        // increase the state tracking the value supplied into the pool
        _depositedATokens += sharesMinted;

        // return the shares created and the amount of underlying deposited into the pool
        return (sharesMinted, depositAmount);
    }

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

            // deposit the amount that exceeds the target reserve into the pool
            uint256 sharesMinted = _supplyAavePool(
                proposedUnderlyingReserve - targetReserve
            );
            // set the new reserve amounts
            _setReserves(targetReserve, aTokenReserve + sharesMinted);
            // increase the state tracking the value supplied into the pool
            _depositedATokens += sharesMinted;
        } else {
            // if we haven't reached our max reserve, we don't deposit into the pool
            // set the new reserve amount
            _setReserves(proposedUnderlyingReserve, aTokenReserve);
        }

        return (shares, depositAmount);
    }

    /// @notice Turns unlocked shares into locked shares and vice versa
    /// @param state the status of the shares to convert
    /// @param shares the number of shares to convert
    /// @return the amount of shares that have been converted
    function _convert(ShareState state, uint256 shares)
        internal
        override
        returns (uint256)
    {
        return
            state == ShareState.Locked
                ? _convertLocked(shares)
                : _convertUnlocked(shares);
    }

    /// @notice converts shares from locked to unlocked
    /// @param lockedShares the number of locked shares to convert
    /// @return the amount of shares that have been converted
    function _convertLocked(uint256 lockedShares) internal returns (uint256) {
        // convert the shares to their underlying value
        uint256 amountToConvert = _pricePerShare(lockedShares);
        // get details about reserve state
        (
            uint256 underlyingReserve,
            uint256 aTokenReserve,
            uint256 aTokenReserveAsUnderlying,
            uint256 impliedUnderlyingReserve
        ) = reserveDetails();
        // adjust the value
        uint256 unlockedShares = (amountToConvert *
            totalSupply[UNLOCKED_YT_ID]) / impliedUnderlyingReserve;
        // increase the atoken reserve value
        _setReserves(underlyingReserve, aTokenReserve + lockedShares);

        return unlockedShares;
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
        uint256 unlockedSharesAsUnderlying = (unlockedShares *
            impliedUnderlyingReserve) /
            (unlockedShares + totalSupply[UNLOCKED_YT_ID]);

        // comput amount of shares proportional to the underlying value of the unlocked shares
        uint256 lockedShares = _sharesPerDollar(unlockedSharesAsUnderlying);

        // adjust reserve value
        _setReserves(underlyingReserve, aTokenReserve - unlockedShares);

        return lockedShares;
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
    /// @param shares the number of shares to withdraw
    /// @param to the address to send the output funds
    /// @return the amount of funds freed from the redemption
    function _withdrawLocked(uint256 shares, address to)
        internal
        returns (uint256)
    {
        // get the proportional amount of shares in its underlying value
        uint256 amountToWithdraw = _pricePerShare(shares);

        // execute the withdrawal, pool also transfers to the user
        // pool returns the amount of underlying withdrawn
        uint256 amountWithdrawn = pool.withdraw(
            address(token),
            amountToWithdraw,
            to
        );

        // decrease our state for aTokens held by the contract
        _depositedATokens -= amountWithdrawn;

        return amountWithdrawn;
    }

    /// @notice the unlocked version of withdraw
    /// @param shares the number of shares to withdraw
    /// @param to the address to send the output funds
    /// @return the amount of funds freed from the redemption
    function _withdrawUnlocked(uint256 shares, address to)
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

        /////////////// TODO: unsure about the math in this section
        // need some other step in scaling to account for aave's mess
        // get the proportional amount of shares in its underlying value
        uint256 amountToWithdraw = _pricePerShare(shares);

        // TODO: need to do any scaling with implied reserve amount
        // uint256 underlyingDue = (shares * impliedUnderlyingReserve) /
        //     (shares + totalSupply[UNLOCKED_YT_ID]);
        ///////////////// END TODO

        if (amountToWithdraw <= underlyingReserve) {
            // if the withdrawal amount is within the underlying reserves
            // then withdraw from those instead of the actual pool

            // set new reserve amount
            _setReserves(underlyingReserve - amountToWithdraw, aTokenReserve);
            // transfer from the term to the user
            token.transferFrom(address(this), to, amountToWithdraw);
            // since we aren't withdrawing from the pool, our deposited share state remains unchanged
        } else {
            if (amountToWithdraw > aTokenReserveAsUnderlying) {
                // if the withdrawal amount is greater than the atoken reserves as well
                // we distribute from both reserve sources

                // withdraw the entire amount of atoken reserve to the contract
                uint256 amountReceived = pool.withdraw(
                    address(token),
                    aTokenReserve,
                    address(this)
                );

                // transfer the desired withdraw amount to the user
                token.transfer(to, amountToWithdraw);

                // set the state to reflect that all atoken share reserves were burned in the withdraw
                // and the underlying reserves is decreased by the remaining amount
                _setReserves(
                    underlyingReserve - (amountToWithdraw - amountReceived),
                    0
                );

                // decrease the deposited aTokens by the amount withdrawn from the pool
                _depositedATokens -= amountReceived;
            } else {
                // the desired withdrawal amount is covered entirely by the atoken reserve

                // burn from the pool directly to the user
                uint256 amountReceived = pool.withdraw(
                    address(token),
                    amountToWithdraw,
                    to
                );
                // underlying reserve remains unchanged
                // atoken reserve is decreased by the amount burned in the withdrawal
                _setReserves(underlyingReserve, aTokenReserve - amountReceived);

                // decrease the deposited aTokens by the amount withdrawn from the pool
                _depositedATokens -= amountReceived;
            }
        }
        return amountToWithdraw;
    }

    /// @notice Get the underlying amount of tokens per shares given
    /// @param shares The amount of shares you want to know the value of
    /// @param state the status of the shares
    /// @return the amount of underlying the input is worth
    function _underlying(uint256 shares, ShareState state)
        internal
        view
        override
        returns (uint256)
    {
        if (state == ShareState.Locked) {
            return _pricePerShare(shares);
        } else {
            // TODO
        }
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
            uint256(_aTokenReserve)
        );

        aTokenReserveAsUnderlying = _pricePerShare(_aTokenReserve);

        impliedUnderlyingReserve = (underlyingReserve +
            aTokenReserveAsUnderlying);
    }

    function _setReserves(
        uint256 _newUnderlyingReserve,
        uint256 _newATokenReserve
    ) internal {
        _underlyingReserve = uint128(_newUnderlyingReserve);
        _aTokenReserve = uint128(_newATokenReserve);
    }

    /// @notice abstracts the pool supply logic and calculation of difference of shares produced
    /// @param depositAmount the amount of the asset to supply into the pool
    /// @return the amount of aTokens minted from the deposit
    function _supplyAavePool(uint256 depositAmount) internal returns (uint256) {
        // load the balance of aTokens before depositing
        uint256 beforeBalance = aToken.balanceOf(address(this));
        // make the deposit into aave
        pool.supply(address(token), depositAmount, address(this), 0);
        // load the balance of atokens after depositing
        uint256 afterBalance = aToken.balanceOf(address(this));
        // return the difference
        return (afterBalance - beforeBalance);
    }

    // converts the input amount of shares to their proportional value of underlying
    function _pricePerShare(uint256 shares) internal view returns (uint256) {
        // get the balance of the contract
        uint256 contractBalance = aToken.balanceOf(address(this));
        // calculate the input's value proportional to the amount of total shares deposited
        uint256 underlying = (shares * contractBalance) / _depositedATokens;
        return underlying;
    }

    // converts the input value to a proportional number of shares
    function _sharesPerDollar(uint256 amount) internal view returns (uint256) {
        // get the balance of the contract
        uint256 contractBalance = aToken.balanceOf(address(this));
        // calculate the input's value proportional to the amount of total shares deposited
        uint256 shares = (amount * _depositedATokens) / contractBalance;
        return shares;
    }
}
