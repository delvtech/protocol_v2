// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "../Term.sol";
import "../libraries/Authorizable.sol";
import "../interfaces/IYieldAdapter.sol";
import "../interfaces/external/aave/IPool.sol";
import "../interfaces/external/aave/IRewardsController.sol";
import "../interfaces/external/aave/IAToken.sol";

contract AaveProxy is Term {
    IPool public immutable pool;
    IRewardsController public immutable rewardsController;
    IAToken public immutable aToken;

    // the proxy underlying reserve amount
    uint256 private _underlyingReserve;
    // the pool share amount
    uint256 private _atokenReserve;

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
        uint256 depositAmount = balance - _underlyingReserve;

        // load the balance of aTokens before depositing
        uint256 beforeBalance = aToken.balanceOf(address(this));

        // make the deposit into aave
        // adjust the amount deposited by the underlying reserve
        pool.supply(address(token), depositAmount, address(this), 0);

        // load the balance of aTokens after depositing
        uint256 afterBalance = aToken.balanceOf(address(this));

        // calculate the difference in aToken balances to know how many where created on deposit
        uint256 sharesMinted = afterBalance - beforeBalance;

        // return the shares created and the amount of underlying deposited into the pool
        return (sharesMinted, depositAmount);
    }

    /// @notice The unlocked version of deposit
    /// @return tuple (shares minuted, amount underlying used)
    function _depositUnlocked() internal returns (uint256, uint256) {
        // load the contract's balance in underlying
        uint256 balance = token.balanceOf(address(this));
        // adjust the deposit amount by the underlying reserve
        uint256 depositAmount = balance - _underlyingReserve;

        // get the underlying amount that's implied in the proxy
        uint256 impliedUnderlyingReserve = _atokenReserveInUnderlying() +
            _underlyingReserve;

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
            pool.supply(
                address(token),
                proposedUnderlyingReserve - targetReserve,
                address(this),
                0
            );
        } else {
            // if we haven't reached our max reserve, we don't deposit into the pool
            // adjust reserve amount
            _underlyingReserve = proposedUnderlyingReserve;
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
    /// @param amount the number of shares to convert
    /// @return the amount of shares that have been converted
    function _convertLocked(uint256 amount) internal returns (uint256) {
        // get the pool shares into their underlying value
        uint256 atokenInUnderlying = _underlying(amount, ShareState.Locked);
        // get the underlying amount that's implied in the proxy
        uint256 impliedUnderlyingReserve = atokenInUnderlying +
            _underlyingReserve;
        uint256 shares = (atokenInUnderlying * totalSupply[UNLOCKED_YT_ID]) /
            impliedUnderlyingReserve;
        // adjust the atoken reserve value
        _atokenReserve += amount;
        return shares;
    }

    /// @notice converts shares from unlocked to locked
    /// @param amount the number of shares to convert
    /// @return the amount of shares that have been converted
    function _convertUnlocked(uint256 amount) internal returns (uint256) {
        // convert input amount into its corresponding representation in aTokens
        // TODO this calculation
        uint256 amountInAtokens;
        // adjust reserve value
        _atokenReserve -= amountInAtokens;
        return amountInAtokens;
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
        uint256 shares = _underlying(amount, ShareState.Locked);

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
        // get the underlying amount that's implied in the proxy
        uint256 impliedUnderlyingReserve = _atokenReserveInUnderlying() +
            _underlyingReserve;
        // calculate the amount desired from the withdrawal
        uint256 underlyingDue = (amount * impliedUnderlyingReserve) /
            (amount + totalSupply[UNLOCKED_YT_ID]);

        if (underlyingDue <= _underlyingReserve) {
            // if the desired amount is within the proxy's reserves then we
            // withdraw from the reserves instead of the actual pool

            // set new reserve amount
            _underlyingReserve -= underlyingDue;
            // transfer from the proxy to the user
            token.transferFrom(address(this), to, underlyingDue);
        } else {
            // if there isn't enough in the proxy reserve, we withdraw from the actual pool
            uint256 amountReceived = pool.withdraw(
                address(token),
                underlyingDue,
                to
            );
            // adjust the reserve amount
            _atokenReserve -= amountReceived;
            // TODO missing logic from this else block
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

    /// @notice placeholder function for getting the pool reserves in underlying
    function _atokenReserveInUnderlying() internal returns (uint256) {
        return 0;
    }
}
