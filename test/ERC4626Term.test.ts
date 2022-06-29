import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers, waffle } from "hardhat";
import {
  FIFTY_THOUSAND_ETHER,
  MAX_UINT256,
  NINE_THOUSAND_ETHER,
  ONE_ETHER,
  ONE_MILLION_ETHER,
  ONE_THOUSAND_ETHER,
  TEN_THOUSAND_ETHER,
  TWENTY_FIVE_THOUSAND_ETHER,
  ZERO,
} from "test/helpers/constants";
import {
  MockERC20,
  MockERC20__factory,
  MockERC4626,
  MockERC4626Term,
  MockERC4626Term__factory,
  MockERC4626__factory,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";

const { provider } = waffle;

// TEST two deposits and two withdraws in one block
// Refactor to use lock/unlock
//
const MAX_RESERVE = FIFTY_THOUSAND_ETHER;
const TARGET_RESERVE = TWENTY_FIVE_THOUSAND_ETHER;
const VAULT_SHARE_PRICE = ethers.utils.parseEther("0.9");

describe.only("ERC4626Term", () => {
  let token: MockERC20;
  let vault: MockERC4626;
  let term: MockERC4626Term;

  let deployer: SignerWithAddress;
  let user: SignerWithAddress;

  let UNLOCKED_YT_ID: BigNumber;

  before(async () => {
    [deployer, user] = await ethers.getSigners();

    // deploy token
    token = await new MockERC20__factory()
      .connect(deployer)
      .deploy("MockERC20Token", "MET", 18);

    // deploy vault
    vault = await new MockERC4626__factory()
      .connect(deployer)
      .deploy(token.address);

    // deploy term
    term = await new MockERC4626Term__factory()
      .connect(deployer)
      .deploy(vault.address, MAX_RESERVE);

    // get ID to track share total supply
    UNLOCKED_YT_ID = await term.UNLOCKED_YT_ID();

    // set price ratio of vaultShares and underlying
    await token.connect(deployer).mint(deployer.address, TEN_THOUSAND_ETHER);
    await token.connect(deployer).approve(vault.address, MAX_UINT256);
    await vault
      .connect(deployer)
      .deposit(NINE_THOUSAND_ETHER, deployer.address);
    await token.connect(deployer).transfer(vault.address, ONE_THOUSAND_ETHER);

    // mint and set approvals for user on term
    await token.mint(user.address, ONE_MILLION_ETHER);
    await token.connect(user).approve(term.address, MAX_UINT256);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("deployment", () => {
    it("term", async () => {
      expect(await term.vault()).to.be.eq(vault.address);
      expect(await term.underlyingReserve()).to.be.eq(ZERO);
      expect(await term.vaultShareReserve()).to.be.eq(ZERO);
      expect(await term.targetReserve()).to.be.eq(TARGET_RESERVE);
      expect(await term.maxReserve()).to.be.eq(MAX_RESERVE);
      expect(await term.totalSupply(UNLOCKED_YT_ID)).to.be.eq(ZERO);

      expect(await token.balanceOf(term.address)).to.be.eq(ZERO);
      expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
    });

    it("vault", async () => {
      expect(await vault.totalAssets()).to.be.eq(TEN_THOUSAND_ETHER);
      expect(await vault.totalSupply()).to.be.eq(NINE_THOUSAND_ETHER);
      expect(await vault.previewDeposit(ONE_ETHER)).to.be.eq(VAULT_SHARE_PRICE);
    });
  });

  describe("ShareState.Unlocked", () => {
    describe("_deposit", () => {
      describe("initial deposit - balances, reserves & supply @ zero", () => {
        it("initial state", async () => {
          // token balances, reserves and shares issued should be zero
          expect(await term.underlyingReserve()).to.be.eq(ZERO);
          expect(await token.balanceOf(term.address)).to.be.eq(ZERO);
          expect(await term.vaultShareReserve()).to.be.eq(ZERO);
          expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
          expect(await term.totalSupply(UNLOCKED_YT_ID)).to.be.eq(ZERO);
        });

        it("should issue shares without depositing to the vault when underlying deposited + reserve is BELOW the max reserve", async () => {
          const now = Math.floor(Date.now() / 1000);
          // tx
          const receipt = await (
            await term.connect(user).lock(
              [],
              [],
              100,
              user.address,
              user.address,
              now,
              806774400 // unix timestamp from the past
            )
          ).wait(1);

          expect(receipt.status).to.be.eq(1);
          //   // as it is the initial deposit, shares issued should match amount of
          //   // underlying deposited 1:1
          //   const [
          //     {
          //       args: { shares },
          //     },
          //   ] = await term.queryFilter(
          //     term.filters.MockDeposit(user.address),
          //     receipt.blockHash
          //   );
          //   expect(shares).to.be.eq(ONE_THOUSAND_ETHER);
          //   // as the underlying amount the user deposited plus the existing
          //   // underlying reserve is less than the max reserve, no deposit into the
          //   // vault should occur
          //   const vaultDepositEvents = await vault.queryFilter(
          //     vault.filters.Deposit(user.address),
          //     receipt.blockHash
          //   );
          //   expect(vaultDepositEvents).to.be.empty;
          //   // reserves and term token balances
          //   expect(await term.underlyingReserve()).to.be.eq(ONE_THOUSAND_ETHER);
          //   expect(await token.balanceOf(term.address)).to.be.eq(
          //     ONE_THOUSAND_ETHER
          //   );
          //   expect(await term.vaultShareReserve()).to.be.eq(ZERO);
          //   expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
        });

        it("should issue shares, depositing a portion of underlying to the vault when underlying deposited + reserve is ABOVE the max reserve", async () => {
          // tx
          // const receipt = await (
          //   await term
          //     .connect(user)
          //     .deposit(ShareState.Unlocked, ONE_HUNDRED_THOUSAND_ETHER)
          // ).wait(1);
          // expect(receipt.status).to.be.eq(1);
          // // As it is the initial deposit, shares issued should match amount of
          // // underlying deposited 1:1
          // const [
          //   {
          //     args: { shares },
          //   },
          // ] = await term.queryFilter(
          //   term.filters.MockDeposit(user.address),
          //   receipt.blockHash
          // );
          // expect(shares).to.be.eq(ONE_HUNDRED_THOUSAND_ETHER);
          // // As the underlying amount the user deposited plus the existing
          // // underlying reserve is greater than the max reserve, an amount of
          // // underlying is siphoned to meet the targetReserve and the rest is
          // // deposited into the vault, exchanged for an amount of vaultShares
          // const vaultDepositEvents = await vault.queryFilter(
          //   vault.filters.Deposit(),
          //   receipt.blockHash
          // );
          // expect(vaultDepositEvents).to.not.be.empty;
          // const [
          //   {
          //     args: {
          //       assets: underlyingDepositedToVault,
          //       shares: vaultShares,
          //       caller,
          //     },
          //   },
          // ] = vaultDepositEvents;
          // expect(caller).to.be.eq(term.address);
          // expect(underlyingDepositedToVault).to.be.eq(
          //   SEVENTY_FIVE_THOUSAND_ETHER
          // );
          // const expectedVaultShares =
          //   SEVENTY_FIVE_THOUSAND_ETHER.mul(VAULT_SHARE_PRICE).div(ONE_ETHER);
          // expect(vaultShares).to.be.eq(expectedVaultShares);
          // // reserves and term token balances
          // expect(await term.underlyingReserve()).to.be.eq(TARGET_RESERVE);
          // expect(await token.balanceOf(term.address)).to.be.eq(TARGET_RESERVE);
          // expect(await term.vaultShareReserve()).to.be.eq(expectedVaultShares);
          // expect(await vault.balanceOf(term.address)).to.be.eq(
          //   expectedVaultShares
          // );
        });
      });

      // describe("typical deposit - existing balances, reserves & supply", () => {
      //   beforeEach(async () => {
      //     // set initial state by doing an "initial" deposit
      //     await term.connect(user).deposit(
      //       ShareState.Unlocked,
      //       FIVE_HUNDRED_THOUSAND_ETHER.add(TWENTY_FIVE_THOUSAND_ETHER) // 525K
      //     );
      //     // we must set totalSupply correctly as it's managed external to the contract
      //     await term.connect(user).setTotalSupply(
      //       FIVE_HUNDRED_THOUSAND_ETHER.add(TWENTY_FIVE_THOUSAND_ETHER) // 525K
      //     );
      //   });

      //   it("initial state", async () => {
      //     // token balances, reserves and shares issued should be as expected
      //     expect(await term.underlyingReserve()).to.be.eq(TARGET_RESERVE);
      //     expect(await token.balanceOf(term.address)).to.be.eq(TARGET_RESERVE);
      //     expect(await term.vaultShareReserve()).to.be.eq(
      //       FOUR_HUNDRED_AND_FIFTY_THOUSAND_ETHER
      //     );
      //     expect(await vault.balanceOf(term.address)).to.be.eq(
      //       FOUR_HUNDRED_AND_FIFTY_THOUSAND_ETHER
      //     );
      //     expect(await term.totalSupply(UNLOCKED_YT_ID)).to.be.eq(
      //       FIVE_HUNDRED_AND_TWENTY_FIVE_THOUSAND_ETHER
      //     );
      //   });

      //   it("should issue shares without depositing to the vault when underlying deposited + reserve is BELOW the max reserve", async () => {
      //     // tx
      //     const receipt = await (
      //       await term
      //         .connect(user)
      //         .deposit(ShareState.Unlocked, ONE_THOUSAND_ETHER)
      //     ).wait(1);
      //     expect(receipt.status).to.be.eq(1);

      //     const [
      //       {
      //         args: { shares },
      //       },
      //     ] = await term.queryFilter(
      //       term.filters.MockDeposit(user.address),
      //       receipt.blockHash
      //     );

      //     expect(shares).to.be.eq(ONE_THOUSAND_ETHER); // actually 1:1 as share price only changes when interest accrues

      //     // no vault deposit event should occur
      //     const vaultDepositEvents = await vault.queryFilter(
      //       vault.filters.Deposit(user.address),
      //       receipt.blockHash
      //     );
      //     expect(vaultDepositEvents).to.be.empty;

      //     // reserves and term token balances
      //     expect(await term.underlyingReserve()).to.be.eq(
      //       TWENTY_SIX_THOUSAND_ETHER
      //     );
      //     expect(await token.balanceOf(term.address)).to.be.eq(
      //       TWENTY_SIX_THOUSAND_ETHER
      //     );
      //     expect(await term.vaultShareReserve()).to.be.eq(
      //       FOUR_HUNDRED_AND_FIFTY_THOUSAND_ETHER
      //     );
      //     expect(await vault.balanceOf(term.address)).to.be.eq(
      //       FOUR_HUNDRED_AND_FIFTY_THOUSAND_ETHER
      //     );
      //   });

      //   it("should issue shares, depositing to the vault when underlying deposited + reserve is ABOVE the max reserve", async () => {
      //     // tx
      //     const receipt = await (
      //       await term
      //         .connect(user)
      //         .deposit(ShareState.Unlocked, ONE_HUNDRED_THOUSAND_ETHER)
      //     ).wait(1);
      //     expect(receipt.status).to.be.eq(1);

      //     const [
      //       {
      //         args: { shares },
      //       },
      //     ] = await term.queryFilter(
      //       term.filters.MockDeposit(user.address),
      //       receipt.blockHash
      //     );
      //     expect(shares).to.be.eq(ONE_HUNDRED_THOUSAND_ETHER);

      //     const vaultDepositEvents = await vault.queryFilter(
      //       vault.filters.Deposit(),
      //       receipt.blockHash
      //     );
      //     expect(vaultDepositEvents).to.not.be.empty;

      //     const [
      //       {
      //         args: {
      //           assets: underlyingDepositedToVault,
      //           shares: vaultShares,
      //           caller,
      //         },
      //       },
      //     ] = vaultDepositEvents;
      //     expect(caller).to.be.eq(term.address);
      //     expect(underlyingDepositedToVault).to.be.eq(
      //       ONE_HUNDRED_THOUSAND_ETHER
      //     );
      //     expect(vaultShares).to.be.eq(NINETY_THOUSAND_ETHER);

      //     expect(await term.underlyingReserve()).to.be.eq(TARGET_RESERVE);
      //     expect(await token.balanceOf(term.address)).to.be.eq(TARGET_RESERVE);
      //     expect(await term.vaultShareReserve()).to.be.eq(
      //       FIVE_HUNDRED_AND_FORTY_THOUSAND_ETHER
      //     );
      //     expect(await vault.balanceOf(term.address)).to.be.eq(
      //       FIVE_HUNDRED_AND_FORTY_THOUSAND_ETHER
      //     );
      //   });
      // });
    });
  });

  // describe("ShareState.Locked", () => {
  //   describe("_deposit", () => {
  //     it("should deposit from adapter into vault successfully", async () => {
  //       const receipt = await (
  //         await term
  //           .connect(user)
  //           .deposit(ShareState.Locked, TEN_THOUSAND_ETHER)
  //       ).wait(1);

  //       expect(receipt.status).to.be.eq(1);

  //       const [
  //         {
  //           args: { shares },
  //         },
  //       ] = await term.queryFilter(
  //         term.filters.MockDeposit(user.address),
  //         receipt.blockHash
  //       );

  //       expect(shares).to.be.eq(NINE_THOUSAND_ETHER);
  //     });
  //   });
  // });
});
