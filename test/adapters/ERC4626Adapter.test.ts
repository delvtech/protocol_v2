import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { zeroAddress } from "ethereumjs-util";
import { ContractReceipt, Event } from "ethers";
import { ethers, waffle } from "hardhat";
import {
  FIFTY_THOUSAND_ETHER,
  ONE_MILLION_ETHER,
  ONE_THOUSAND_ETHER,
  ZERO,
} from "test/helpers/constants";
import {
  MockERC20,
  MockERC20__factory,
  MockERC4626,
  MockERC4626Adapter,
  MockERC4626Adapter__factory,
  MockERC4626__factory,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "../helpers/snapshots";

const { provider } = waffle;

enum ShareState {
  UNLOCKED,
  LOCKED,
}

describe("ERC4626Adapter", () => {
  let token: MockERC20;
  let vault: MockERC4626;
  let adapter: MockERC4626Adapter;

  let deployer: SignerWithAddress;
  let user: SignerWithAddress;
  let whale: SignerWithAddress;

  before(async () => {
    [deployer, user, whale] = await ethers.getSigners();
    token = await new MockERC20__factory()
      .connect(deployer)
      .deploy("MockERC20Token", "MET", 18);

    vault = await new MockERC4626__factory()
      .connect(deployer)
      .deploy(token.address);

    adapter = await new MockERC4626Adapter__factory()
      .connect(deployer)
      .deploy(vault.address, FIFTY_THOUSAND_ETHER);

    token.connect(user);
    vault.connect(user);
    adapter.connect(user);

    await createSnapshot(provider);
  });

  // beforeEach(async () => {
  //   await createSnapshot(provider);
  // });

  // afterEach(async () => {
  //   await restoreSnapshot(provider);
  // });

  // describe("deployment", () => {
  //   it("should set the correct limit", async () => {
  //     expect(await adapter.reserveLimit()).to.be.eq(FIFTY_THOUSAND_ETHER);
  //   });
  //   it("should set the correct vault address", async () => {
  //     expect(await adapter.vault()).to.be.eq(vault.address);
  //   });
  // });

  describe("_deposit", () => {
    describe.only("LOCKED", () => {
      let receipt: ContractReceipt;

      before(async () => {
        // Issue underlying to the to the adapter contract
        await token.mint(adapter.address, ONE_THOUSAND_ETHER);
      });

      after(async () => {
        await restoreSnapshot(provider);
      });

      // it("should be an initial balance of underlying for the adapter", async () => {
      //   expect(await token.balanceOf(adapter.address)).to.be.eq(
      //     ONE_THOUSAND_ETHER
      //   );
      // });

      // it("should be no deposits or shares issued by the vault", async () => {
      //   expect(await vault.totalAssets()).to.be.eq(ZERO);
      //   expect(await vault.totalSupply()).to.be.eq(ZERO);
      // });

      it.only("should deposit from adapter into vault successfully", async () => {
        // deposit - mock internally calls adapter._deposit
        receipt = await adapter
          .deposit(ShareState.LOCKED)
          .then(async (tx) => await tx.wait(1));

        expect(receipt.status).to.be.eq(1);
      });

      // it("should have transferred balance of underlying out of the adapter", async () => {
      //   expect(await token.balanceOf(adapter.address)).to.be.eq(ZERO);
      // });

      // it("should be an equal amount of underlying asset deposited and shares issued", async () => {
      //   expect(await vault.totalAssets()).to.be.eq(ONE_THOUSAND_ETHER);
      //   expect(await vault.totalSupply()).to.be.eq(ONE_THOUSAND_ETHER);
      // });

      // it("should be a balance of vault shares for the adapter", async () => {
      //   expect(await vault.balanceOf(adapter.address)).to.be.eq(
      //     ONE_THOUSAND_ETHER
      //   );
      // });

      // it("should have emitted the underlying token's transfer event", async () => {
      //   const transferEvents = await token.queryFilter(
      //     token.filters.Transfer(adapter.address, vault.address),
      //     receipt.blockHash
      //   );
      //   expect(transferEvents.length).to.be.eq(1);
      //   expect(transferEvents[0].args.from).to.be.eq(adapter.address);
      //   expect(transferEvents[0].args.to).to.be.eq(vault.address);
      //   expect(transferEvents[0].args.value).to.be.eq(ONE_THOUSAND_ETHER);
      // });

      // it("should have emitted the vault's deposit event", async () => {
      //   const depositEvents = await vault.queryFilter(
      //     vault.filters.Deposit(adapter.address, adapter.address),
      //     receipt.blockHash
      //   );
      //   expect(depositEvents.length).to.be.eq(1);
      //   expect(depositEvents[0].args.caller).to.be.eq(adapter.address);
      //   expect(depositEvents[0].args.owner).to.be.eq(adapter.address);
      //   expect(depositEvents[0].args.assets).to.be.eq(ONE_THOUSAND_ETHER);
      //   expect(depositEvents[0].args.shares).to.be.eq(ONE_THOUSAND_ETHER);
      // });

      // it("should have emitted the vault's transfer event", async () => {
      //   const transferEvents = await vault.queryFilter(
      //     vault.filters.Transfer(ethers.constants.AddressZero, adapter.address),
      //     receipt.blockHash
      //   );
      //   expect(transferEvents.length).to.be.eq(1);
      //   expect(transferEvents[0].args.from).to.be.eq(
      //     ethers.constants.AddressZero
      //   );
      //   expect(transferEvents[0].args.to).to.be.eq(adapter.address);
      //   expect(transferEvents[0].args.value).to.be.eq(ONE_THOUSAND_ETHER);
      // });
    });

    describe("UNLOCKED", () => {
      before(async () => {
        // Issue underlying to the to the adapter contract
        await token.mint(whale.address, ONE_MILLION_ETHER);
      });

      after(async () => {
        await restoreSnapshot(provider);
      });

      it("should be a balance of vault shares exceeding the vault reserve limit", async () => {});
    });
  });

  // describe("_withdraw", async () => {
  // });

  // describe("_convert", async () => {
  // });

  // describe("_underlying", async () => {
  // });
});
