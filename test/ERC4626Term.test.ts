import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers, waffle } from "hardhat";
import {
  FIFTY_THOUSAND_ETHER,
  MAX_UINT256,
  NINE_THOUSAND_ETHER,
  ONE_ETHER,
  ONE_HUNDRED_THOUSAND_ETHER,
  ONE_MILLION_ETHER,
  ONE_THOUSAND_ETHER,
  SEVENTY_FIVE_THOUSAND_ETHER,
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

enum ShareState {
  Locked,
  Unlocked,
}

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
      .deploy(vault.address, FIFTY_THOUSAND_ETHER);

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

  describe.only("deployment", () => {
    it("term", async () => {
      expect(await term.vault()).to.be.eq(vault.address);
      expect(await term.underlyingReserve()).to.be.eq(ZERO);
      expect(await term.vaultShareReserve()).to.be.eq(ZERO);
      expect(await term.targetReserve()).to.be.eq(TWENTY_FIVE_THOUSAND_ETHER);
      expect(await term.maxReserve()).to.be.eq(FIFTY_THOUSAND_ETHER);
      expect(await token.balanceOf(term.address)).to.be.eq(ZERO);
      expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
    });

    it("vault", async () => {
      expect(await vault.totalAssets()).to.be.eq(TEN_THOUSAND_ETHER);
      expect(await vault.totalSupply()).to.be.eq(NINE_THOUSAND_ETHER);
      expect(await vault.previewDeposit(ONE_ETHER)).to.be.eq(
        ethers.utils.parseEther("0.9")
      );
    });
  });
  describe("ShareState.Locked", () => {
    describe("_deposit", () => {
      beforeEach(async () => {
        await createSnapshot(provider);
      });

      afterEach(async () => {
        await restoreSnapshot(provider);
      });

      it("should deposit from adapter into vault successfully", async () => {
        const receipt = await (
          await term
            .connect(user)
            .deposit(ShareState.Locked, ONE_THOUSAND_ETHER)
        ).wait(1);

        expect(receipt.status).to.be.eq(1);
      });

      it("should issue shares equal to the amount of underlying deposited", async () => {
        const [
          {
            args: { shares },
          },
        ] = await term.queryFilter(term.filters.MockDeposit(user.address));

        expect(shares).to.be.eq(ONE_THOUSAND_ETHER);
      });
    });
  });

  describe("ShareState.Unlocked", () => {
    describe("_deposit", () => {
      describe("initial term deposit - deposit below max reserve", () => {
        before(async () => {
          await createSnapshot(provider);
        });

        after(async () => {
          await restoreSnapshot(provider);
        });

        it("should have expected initial state", async () => {
          expect(await term.vault()).to.be.eq(vault.address);
          expect(await term.underlyingReserve()).to.be.eq(ZERO);
          expect(await term.vaultShareReserve()).to.be.eq(ZERO);
        });

        it("should deposit successfully", async () => {
          const receipt = await (
            await term
              .connect(user)
              .deposit(ShareState.Unlocked, ONE_THOUSAND_ETHER)
          ).wait(1);
          expect(receipt.status).to.be.eq(1);
        });

        it("should issue shares equal to the amount of underlying deposited", async () => {
          const [
            {
              args: { shares },
            },
          ] = await term.queryFilter(term.filters.MockDeposit(user.address));

          expect(shares).to.be.eq(ONE_THOUSAND_ETHER);
        });
        it("should have added underlying to the underlying reserve", async () => {
          expect(await term.underlyingReserve()).to.be.eq(ONE_THOUSAND_ETHER);
          expect(await token.balanceOf(term.address)).to.be.eq(
            ONE_THOUSAND_ETHER
          );
        });
        it("should not have altered the vaultShareReserve", async () => {
          expect(await term.vaultShareReserve()).to.be.eq(ZERO);
          expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
        });
      });

      describe("initial term deposit - deposit above max reserve", () => {
        before(async () => {
          await createSnapshot(provider);
          await token.mint(user.address, ONE_HUNDRED_THOUSAND_ETHER);
          await token.connect(user).approve(term.address, MAX_UINT256);
        });

        after(async () => {
          await restoreSnapshot(provider);
        });

        it("should have expected initial state", async () => {
          expect(await term.vault()).to.be.eq(vault.address);
          expect(await term.underlyingReserve()).to.be.eq(ZERO);
          expect(await term.vaultShareReserve()).to.be.eq(ZERO);
        });
        it("should deposit successfully", async () => {
          const receipt = await (
            await term
              .connect(user)
              .deposit(ShareState.Unlocked, ONE_HUNDRED_THOUSAND_ETHER)
          ).wait(1);
          expect(receipt.status).to.be.eq(1);
        });
        it("should issue shares equal to the amount of underlying deposited", async () => {
          const [
            {
              args: { shares },
            },
          ] = await term.queryFilter(term.filters.MockDeposit(user.address));

          expect(shares).to.be.eq(ONE_HUNDRED_THOUSAND_ETHER);
        });
        it("should have added to the underlying reserve", async () => {
          expect(await term.underlyingReserve()).to.be.eq(
            TWENTY_FIVE_THOUSAND_ETHER
          );
          expect(await token.balanceOf(term.address)).to.be.eq(
            TWENTY_FIVE_THOUSAND_ETHER
          );
        });

        it("should have added to vaultShareReserve", async () => {
          expect(await term.vaultShareReserve()).to.be.eq(
            SEVENTY_FIVE_THOUSAND_ETHER
          );
          expect(await vault.balanceOf(term.address)).to.be.eq(
            SEVENTY_FIVE_THOUSAND_ETHER
          );
        });
      });

      describe("normal deposit - deposit below max reserve", () => {
        before(async () => {
          await createSnapshot(provider);
          await token.mint(user.address, ONE_THOUSAND_ETHER);
          await token.connect(user).approve(term.address, MAX_UINT256);

          await term.setUnderlyingReserves(
            TWENTY_FIVE_THOUSAND_ETHER,
            SEVENTY_FIVE_THOUSAND_ETHER
          );
          await term.connect(user).setTotalSupply(ONE_HUNDRED_THOUSAND_ETHER);
        });

        after(async () => {
          await restoreSnapshot(provider);
        });

        it("should have expected initial state", async () => {
          expect(await term.underlyingReserve()).to.be.eq(
            TWENTY_FIVE_THOUSAND_ETHER
          );
          expect(await token.balanceOf(term.address)).to.be.eq(
            TWENTY_FIVE_THOUSAND_ETHER
          );
          expect(await term.vaultShareReserve()).to.be.eq(
            SEVENTY_FIVE_THOUSAND_ETHER
          );
          expect(await vault.balanceOf(term.address)).to.be.eq(
            SEVENTY_FIVE_THOUSAND_ETHER
          );
          expect(await term.totalSupply(UNLOCKED_YT_ID)).to.be.eq(
            ONE_HUNDRED_THOUSAND_ETHER
          );
        });

        it("should deposit successfully", async () => {
          const receipt = await (
            await term
              .connect(user)
              .deposit(ShareState.Unlocked, ONE_THOUSAND_ETHER)
          ).wait(1);
          expect(receipt.status).to.be.eq(1);
        });

        it("should issue shares equal to the amount of underlying deposited", async () => {
          const [
            {
              args: { shares },
            },
          ] = await term.queryFilter(term.filters.MockDeposit(user.address));
          expect(shares).to.be.eq(ONE_THOUSAND_ETHER);
        });

        // it("should ", async () => {
        //   const receipt = await (
        //     await term
        //       .connect(user)
        //       .deposit(ShareState.Unlocked, ONE_HUNDRED_THOUSAND_ETHER)
        //   ).wait(1);
        //   expect(receipt.status).to.be.eq(1);
        // });
      });
    });
  });
});
