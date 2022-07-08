import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import {
  ForwarderFactory,
  MockERC20YearnVault,
  MockFixedPointMath,
  MockYieldAdapter,
  TestERC20,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { getCurrentTimestamp, ONE_YEAR_IN_SECONDS } from "./helpers/time";
import fp from "evm-fp";

const { provider } = waffle;
const YT_FLAG = 2 ** 256;

describe("Convert YT Tests", async () => {
  let signers: SignerWithAddress[];
  let factory: ForwarderFactory;
  let token: TestERC20;
  let vault: MockERC20YearnVault;
  let yieldAdapter: MockYieldAdapter;
  let MockFixedPointMath: MockFixedPointMath;

  before(async () => {
    signers = await ethers.getSigners();

    const mathFactory = await ethers.getContractFactory("MockFixedPointMath");
    MockFixedPointMath = await mathFactory.deploy();

    const factoryFactory = await ethers.getContractFactory(
      "ForwarderFactory",
      signers[0]
    );
    factory = await factoryFactory.deploy();

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

    // set some token balance
    await token.mint(signers[0].address, 7e6);
    // set allowance for the yieldAdapter contract
    await token.connect(signers[0]).approve(yieldAdapter.address, 12e6);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe.only("do the thing", async () => {
    it("fails for invalid asset type", async () => {
      // function fails for assetID's without leading 1
      const ptID = 0;
      const tx = yieldAdapter.convertYT(ptID, 0, signers[0].address, false);
      await expect(tx).to.be.revertedWith("asset ID is not YT");
    });

    it("fails invalid expiry", async () => {
      const start = await getCurrentTimestamp(provider);
      // construct asset ID with 0 expiration
      const id = YT_FLAG + start * 2 ** 128;
      const tx = yieldAdapter.convertYT(id, 0, signers[0].address, false);
      await expect(tx).to.be.revertedWith("invalid expiry");
    });

    it("fails invalid start date", async () => {
      const expiration =
        (await getCurrentTimestamp(provider)) + ONE_YEAR_IN_SECONDS;
      // construct asset ID with 0 start date
      const id = YT_FLAG + expiration;
      const tx = yieldAdapter.convertYT(id, 0, signers[0].address, false);
      await expect(tx).to.be.revertedWith("invalid token start date");
    });

    it("fails for nonexistent term", async () => {
      const start = await getCurrentTimestamp(provider);
      const expiration = start + ONE_YEAR_IN_SECONDS;
      const id = YT_FLAG + start * 2 ** 128 + expiration;
      const tx = yieldAdapter.convertYT(id, 0, signers[0].address, false);
      await expect(tx).to.be.revertedWith("no term for input asset");
    });

    it("fail to convert amount greater than available", async () => {
      const start = await getCurrentTimestamp(provider);
      const expiration = start + ONE_YEAR_IN_SECONDS;
      const id = YT_FLAG + start * 2 ** 128 + expiration;
      // create a term by locking some tokens
      await yieldAdapter.lock(
        [],
        [],
        1e3,
        signers[0].address,
        signers[0].address,
        start,
        expiration
      );
      const tx = yieldAdapter.convertYT(id, 1e7, signers[0].address, false);
      await expect(tx).to.be.revertedWith("inadequate share balance");
    });

    it("successful non-compound conversion", async () => {
      const start = await getCurrentTimestamp(provider);
      const expiration = start + ONE_YEAR_IN_SECONDS;
      const id = YT_FLAG + start * 2 ** 128 + expiration;

      const vaultBalance = await token.balanceOf(vault.address);

      // create a term by locking some tokens
      await yieldAdapter.lock(
        [],
        [],
        1e4,
        signers[0].address,
        signers[0].address,
        start,
        expiration
      );
      await yieldAdapter.convertYT(id, 1e2, signers[0].address, false);
      // check that yt balance decreased for original ID
      const balance = await yieldAdapter.balanceOf(id, signers[0].address);
      expect(balance).to.be.eq(1e4 - 1e2);
      // check balance at new ID?
      // check that vault balance decreased
      const newBalance = await token.balanceOf(vault.address);
      expect(newBalance).to.be.equal(vaultBalance.toNumber() - 1e2);
    });

    it("successful compound conversion", async () => {
      const start = await getCurrentTimestamp(provider);
      const expiration = start + ONE_YEAR_IN_SECONDS;
      const id = YT_FLAG + start * 2 ** 128 + expiration;
      // create a term by locking some tokens
      await yieldAdapter.lock(
        [],
        [],
        1e4,
        signers[0].address,
        signers[0].address,
        start,
        expiration
      );
      await yieldAdapter.convertYT(id, 1e2, signers[0].address, true);
      // check that yt balance decreased for original ID
      const balance = await yieldAdapter.balanceOf(id, signers[0].address);
      // check balance at new YT id?
      // check PT balance?
    });
    // how to run into this case?
    // it("fail compound conversion with nonzero interest", async () => {
    //     // AKA run into nonzero discount require
    // });
  });
});
