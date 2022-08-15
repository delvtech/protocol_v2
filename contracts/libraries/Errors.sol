/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

library ElementError {
    ///
    /// ##################
    /// ### MultiToken ###
    /// ##################
    ///
    /// Indicates that the caller is not a create2 validated ERC20 bridge
    error MultiToken__OnlyLinker_NonLinkerCaller();
    /// MultiToken.batchTransfer called with a `from` argument of 0x0
    error MultiToken__BatchTransfer_ZeroAddressFrom();
    /// MultiToken.batchTransfer called with a `to` argument of 0x0
    error MultiToken__BatchTransfer_ZeroAddressTo();
    /// MultiToken.batchTransfer called with `ids` and `values` args of different length
    error MultiToken__BatchTransfer_InputLengthMismatch();
    /// MultiToken.permitForAll called with a ``deadline` argument earlier than the current time
    error MultiToken__PermitForAll_ExpiredDeadline();
    /// MultiToken.permitForAll called with a `owner` argument specifying the zero address
    error MultiToken__PermitForAll_OwnerIsZeroAddress();
    /// MultiToken.permitForAll could not match the owner from the derived signer
    error MultiToken__PermitForAll_OwnerIsNotSigner();

    ///
    /// ###################
    /// ### ERC20Permit ###
    /// ###################
    ///
    error ERC20Permit__TransferFrom_InsufficientBalance();
    error ERC20Permit__TransferFrom_InsufficientAllowance();
    error ERC20Permit__Permit_OwnerIsZeroAddress();
    error ERC20Permit__Permit_OwnerIsNotSigner();
    error ERC20Permit__Permit_Expired();
    error ERC20Permit__Permit_InvalidSignature();

    ///
    /// ###################
    /// ### ERC20Forwarder ###
    /// ###################
    ///
    error ERC20Forwarder__Permit_OwnerIsZeroAddress();
    error ERC20Forwarder__Permit_OwnerIsNotSigner();
    error ERC20Forwarder__Permit_Expired();

    ///
    /// ############
    /// ### Term ###
    /// ############
    ///
    /// Term.lock called specifying an expiration time for the term which is
    /// earlier than the current time
    error Term__Lock_BeyondExpirationDate();
    /// Term.lock called with an unsorted assetIds argument, should sequence
    /// id's in order lowest to highest
    error Term__Lock_UnsortedAssetIds();
    /// Term.depositUnlocked attempted to redeem a PT which has not expired
    error Term__DepositUnlocked_PrincipalTokenHasNotExpired();
    /// Term.unlock called with an unsorted assetIds argument, should sequence
    /// id's in order lowest to highest
    error Term__Unlock_UnsortedAssetIds();
    /// Term._createYT may backdate yield tokens to a pre-existing term but this
    /// is not allowed if that term does not exist
    error Term__CreateYT_TermDoesNotExist();
    /// Term._releaseAsset redeems an expired PT or YT but must requires they
    /// are expired
    error Term__ReleaseAsset_AssetNotExpired();
    /// Term._convertYT validates `assetId` argument to be a YT
    error Term__ConvertYT_AssetIdDoesNotMatchYieldToken();
    /// Term._convertYT
    error Term__ConvertYT_ExpirationDateIsZero();
    error Term__ConvertYT_StartDateIsZero();
    error Term__ConvertYT_TermDoesNotExist();
    error Term__ConvertYT_YieldTokenBackdated();
    error Term__Redeem_IncongruentPrincipalAndYieldTokenIds();

    ///
    /// ###################
    /// ### ERC4626Term ###
    /// ###################
    error ERC4626Term__ConvertUnlocked_VaultShareReserveTooLow();
    ///
    /// ###################
    /// ### CompoundV3Term ###
    /// ###################
    error CompoundV3Term__ConvertUnlocked_VaultShareReserveTooLow();

    ///
    /// ##########
    /// ### LP ###
    /// ##########
    ///
    error LP__DepositUnderlying_BeyondExpirationDate();
    error LP__DepositUnderlying_ExceededSlippageLimit();
    error LP__DepositBonds_BeyondExpirationDate();
    error LP__DepositBonds_ExceededSlippageLimit();
    error LP__Rollover_BeyondExpirationDate();
    error LP__Rollover_ExceededSlippageLimit();
    error LP__DepositFromShares_PoolNotInitialized();
    error LP__DepositFromShares_BeyondExpirationDate();

    ///
    /// ############
    /// ### Pool ###
    /// ############
    ///
    error Pool__Constructor_ZeroAddressGovernanceContract();
    error Pool__RegisterPoolId_BeyondExpirationDate();
    error Pool__RegisterPoolId_PoolAlreadyInitialized();
    error Pool__RegisterPoolId_ZeroTimeStretch();
    error Pool__RegisterPoolId_ZeroUnderlyingDeposit();
    error Pool__TradeBonds_BeyondExpirationDate();
    error Pool__TradeBonds_PoolNotInitialized();
    error Pool__TradeBonds_ExceededSlippageLimit();
    error Pool__PurchaseYT_BeyondExpirationDate();
    error Pool__PurchaseYT_PoolNotInitialized();
    error Pool__PurchaseYT_ExceededSlippageLimit();
    error Pool__PurchaseYT_IncorrectEstimateOfPrincipalTokens();

    ///
    /// ############
    /// ### TWAROracle ###
    /// ############
    ///
    error TWAROracle__InitializeBuffer_IncorrectBufferLength();
    error TWAROracle__InitializeBuffer_BufferAlreadyInitialized();
    error TWAROracle__InitializeBuffer_ZeroMinTimeStep();
    error TWAROracle__ReadSumAndTimeStampForPool_IndexOutOfBounds();
    error TWAROracle__CalculateAverageWeightedValue_NotEnoughElements();

    ///
    /// ######################
    /// ### FixedPointMath ###
    /// ######################
    ///
    error FixedPointMath__Add_Overflow();
    error FixedPointMath__Sub_Overflow();
    error FixedPointMath__Exp_InvalidExponent();
    error FixedPointMath__Ln_NegativeOrZeroInput();
    error FixedPointMath__Ln_NegativeInput();

    ///
    /// #####################
    /// ### Authorizable ####
    /// #####################
    ///
    error Authorizable__OnlyOwner_SenderMustBeOwner();
    error Authorizable__OnlyAuthorized_SenderMustBeAuthorized();
}
