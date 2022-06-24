import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { MockYieldAdapter } from "typechain/MockYieldAdapter";
import { MockERC20YearnVault } from "typechain/MockERC20YearnVault";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { TestERC20 } from "typechain/TestERC20";
import { ForwarderFactory } from "typechain/ForwarderFactory";

const { provider } = waffle;

// TODO: this runs me into backdating when I use this so I think it's bad block math/setup
//       is it worth it to try to make it work?
async function getTimestamp() {
  return (await ethers.provider.getBlock("latest")).timestamp;
}

describe("Deposit Tests", async () => {
  const SECONDS_IN_YEAR = 31536000;

  let token: TestERC20;
  let vault: MockERC20YearnVault;
  let yieldAdapter: MockYieldAdapter;
  let factory: ForwarderFactory;
  let signers: SignerWithAddress[];

  before(async () => {
    signers = await ethers.getSigners();
    const tokenFactory = await ethers.getContractFactory(
      "TestERC20",
      signers[0]
    );
    token = await tokenFactory.deploy("token", "TKN", 18);
    const vaultFactory = await ethers.getContractFactory(
      "MockERC20YearnVault",
      signers[0]
    );
    vault = await vaultFactory.deploy(token.address);
    const factoryFactory = await ethers.getContractFactory(
      "ForwarderFactory",
      signers[0]
    );
    factory = await factoryFactory.deploy();
    const adapterFactory = await ethers.getContractFactory(
      "MockYieldAdapter",
      signers[0]
    );
    yieldAdapter = await adapterFactory.deploy(
      vault.address,
      await factory.ERC20LINK_HASH(),
      factory.address,
      token.address
    );

    // TODO: probably loop this for multiple users so cleaner
    // mint some tokens
    await token.mint(signers[0].address, 7e6);
    await token.mint(signers[1].address, 7e6);
    // set an allowance
    await token.connect(signers[0]).approve(yieldAdapter.address, 12e6);
    await token.connect(signers[1]).approve(yieldAdapter.address, 12e6);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe.only("Lock", async () => {
    it("Fails invalid expiry", async () => {
      const tx = yieldAdapter.lock(
        [],
        [],
        100,
        signers[0].address,
        signers[0].address,
        Math.floor(Date.now() / 1000),
        806774400 // unix timestamp from the past
      );
      await expect(tx).to.be.revertedWith("todo nice error");
    });

    it("Single user successfully deposit underlying", async () => {
      // create beginning timestamp
      const start = Math.floor(Date.now() / 1000);
      // create expiry timestamp in the future
      const expiration = start + SECONDS_IN_YEAR;
      await yieldAdapter.lock(
        [],
        [],
        5,
        signers[0].address,
        signers[0].address,
        start,
        expiration
      );
      // check that user's balance decreased
      expect(await token.balanceOf(signers[0].address)).to.equal(7e6 - 5);
      // check that vault's balance increased
      expect(await token.balanceOf(vault.address)).to.equal(5);
    });

    // TODO: probably a copy of this with some waiting between & different timestamps
    it("Multiple users successfully deposit underlying", async () => {
      // create beginning timestamp
      const start = Math.floor(Date.now() / 1000);
      // create expiry timestamp in the future
      const expiration = start + SECONDS_IN_YEAR;
      await yieldAdapter
        .connect(signers[0])
        .lock(
          [],
          [],
          5,
          signers[0].address,
          signers[0].address,
          start,
          expiration
        );
      await yieldAdapter
        .connect(signers[1])
        .lock(
          [],
          [],
          5,
          signers[1].address,
          signers[1].address,
          start,
          expiration
        );
      // check that user's balance decreased
      expect(await token.balanceOf(signers[0].address)).to.equal(7e6 - 5);
      expect(await token.balanceOf(signers[1].address)).to.equal(7e6 - 5);
      // check that vault's balance increased
      expect(await token.balanceOf(vault.address)).to.equal(10);
    });

    it("Deposit underlying with zero expiry", async () => {
      // create beginning timestamp
      const now = Math.floor(Date.now() / 1000);
      const tx = yieldAdapter.lock(
        [],
        [],
        5,
        signers[0].address,
        signers[0].address,
        now,
        0
      );
      await expect(tx).to.be.reverted;
      // TODO: should not revert, fix the logic here
    });

    it("Valid backdating deposit", async () => {
      // TODO: this is not structured correctly
      const tx = yieldAdapter.lock(
        [],
        [],
        100,
        signers[0].address,
        signers[0].address,
        Math.floor(Date.now() / 1000),
        806774400 // unix timestamp from the past
      );
      await expect(tx).to.be.revertedWith("todo nice error");
    });
  });
  describe.only("Unlock", async () => {
    it("Unlock some reserves", async () => {
      // deposit some underlying
      const now = Math.floor(Date.now() / 1000);
      const expiration = now + 1;
      await yieldAdapter.lock(
        [],
        [],
        5,
        signers[0].address,
        signers[0].address,
        now,
        expiration
      );
      const id = (1 << (255 + now)) << (128 + expiration);
      const tx = await yieldAdapter.unlock(signers[0].address, [id], [1]);
      // think I need to wait here, gives a weird division by zero
    });
  });
});
