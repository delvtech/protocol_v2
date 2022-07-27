import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import {
  ForwarderFactory,
  MockERC20YearnVault,
  MockYieldAdapter,
  MockERC20Permit,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import {
  getCurrentTimestamp,
  advanceTime,
  SIX_MONTHS_IN_SECONDS,
  ONE_YEAR_IN_SECONDS,
} from "./helpers/time";
import { getTokenId } from "./helpers/tokenIds";

const { provider } = waffle;

describe("Convert YT Tests", async () => {
  let signers: SignerWithAddress[];
  let factory: ForwarderFactory;
  let token: MockERC20Permit;
  let vault: MockERC20YearnVault;
  let yieldAdapter: MockYieldAdapter;

  before(async () => {
    signers = await ethers.getSigners();

    const factoryFactory = await ethers.getContractFactory(
      "ForwarderFactory",
      signers[0]
    );
    factory = await factoryFactory.deploy();

    const tokenFactory = await ethers.getContractFactory(
      "MockERC20Permit",
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
      signers[0].address,
      await factory.ERC20LINK_HASH(),
      factory.address,
      token.address
    );

    // set some token balance
    await token.mint(signers[0].address, 7e6);
    await token.mint(signers[1].address, 7e6);
    // set allowance for the yieldAdapter contract
    await token.connect(signers[0]).approve(yieldAdapter.address, 12e6);
    await token.connect(signers[1]).approve(yieldAdapter.address, 12e6);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("YT conversions", async () => {
    beforeEach(async () => {
      await createSnapshot(provider);
    });

    afterEach(async () => {
      await restoreSnapshot(provider);
    });

    it("fails for invalid asset type", async () => {
      // function fails for assetID's without leading 1
      const ptID = 0;
      const tx = yieldAdapter.convertYT(ptID, 0, signers[0].address, false);
      await expect(tx).to.be.revertedWith("asset ID is not YT");
    });

    it("fails invalid expiry", async () => {
      const start = await getCurrentTimestamp(provider);
      const id = getTokenId(start, 0);
      const tx = yieldAdapter.convertYT(id, 0, signers[0].address, false);
      await expect(tx).to.be.revertedWith("invalid expiry");
    });

    it("fails invalid start date", async () => {
      const expiration =
        (await getCurrentTimestamp(provider)) + ONE_YEAR_IN_SECONDS;
      // construct asset ID with 0 start date
      const id = getTokenId(0, expiration);
      const tx = yieldAdapter.convertYT(id, 0, signers[0].address, false);
      await expect(tx).to.be.revertedWith("invalid token start date");
    });

    it("fails for nonexistent term", async () => {
      const start = await getCurrentTimestamp(provider);
      const expiration = start + ONE_YEAR_IN_SECONDS;
      const id = getTokenId(start, expiration);
      const tx = yieldAdapter.convertYT(id, 0, signers[0].address, false);
      await expect(tx).to.be.revertedWith("no term for input asset");
    });

    it("fail to convert amount greater than available", async () => {
      const start = await getCurrentTimestamp(provider);
      const expiration = start + ONE_YEAR_IN_SECONDS;
      const id = getTokenId(start, expiration);
      // create a term by locking some tokens
      await yieldAdapter.lock(
        [],
        [],
        1e3,
        false,
        signers[0].address,
        signers[0].address,
        start,
        expiration
      );
      const tx = yieldAdapter.convertYT(id, 1e7, signers[0].address, false);
      await expect(tx).to.be.revertedWith(
        "Arithmetic operation underflowed or overflowed outside of an unchecked block"
      );
    });

    // This test doesn't make sense bc there is no passage of time to accrue interest.
    // The reason it used to pass was bc we weren't dividing _underlying by one in the YieldAdapter
    it.skip("successful non-compound conversion", async () => {
      const convertAmount = 1e2;
      const start = await getCurrentTimestamp(provider);
      const expiration = start + ONE_YEAR_IN_SECONDS;
      const id = getTokenId(start, expiration);

      // create a term by locking some tokens
      await yieldAdapter.lock(
        [],
        [],
        1e4,
        false,
        signers[0].address,
        signers[0].address,
        start,
        expiration
      );
      // track the vault balance before conversion
      const vaultBalance = await token.balanceOf(vault.address);
      // execute the conversion
      await yieldAdapter.convertYT(
        id,
        convertAmount,
        signers[0].address,
        false
      );
      // check that yt balance decreased for ID
      const ytBalance = await yieldAdapter.balanceOf(id, signers[0].address);
      expect(ytBalance).to.be.equal(1e4 - convertAmount);
      // check that vault balance decreased
      const newBalance = await token.balanceOf(vault.address);
      expect(newBalance).to.be.equal(
        vaultBalance.toNumber() - convertAmount + 1
      ); // unsure of this +1 here
    });

    // The test "framework" doesn't properly accrue interest so this test will never work.
    // The reason it used to pass was bc we weren't dividing _underlying by one in the YieldAdapter
    it.skip("successful non-compound conversion after time passes", async () => {
      const convertAmount = 2e2;
      const start = await getCurrentTimestamp(provider);
      const expiration = start + 2 * ONE_YEAR_IN_SECONDS;
      const id = getTokenId(start, expiration);

      // create a term by locking some tokens
      await yieldAdapter.lock(
        [],
        [],
        1e4,
        false,
        signers[0].address,
        signers[0].address,
        start,
        expiration
      );

      // advance time
      await advanceTime(provider, SIX_MONTHS_IN_SECONDS);

      // track the vault balance before conversion
      const vaultBalance = await token.balanceOf(vault.address);
      // execute the conversion
      await yieldAdapter.convertYT(
        id,
        convertAmount,
        signers[0].address,
        false
      );
      // check that yt balance decreased for ID
      const ytBalance = await yieldAdapter.balanceOf(id, signers[0].address);
      expect(ytBalance).to.be.equal(1e4 - convertAmount);
      // check that vault balance decreased
      const newBalance = await token.balanceOf(vault.address);
      expect(newBalance).to.be.equal(
        vaultBalance.toNumber() - convertAmount + 1
      ); // unsure of this +1 here
    });

    it("successful compound conversion", async () => {
      const convertAmount = 1e2;
      const start = await getCurrentTimestamp(provider);
      const expiration = start + ONE_YEAR_IN_SECONDS;
      const id = getTokenId(start, expiration);
      // create a term by locking some tokens
      await yieldAdapter.lock(
        [],
        [],
        1e4,
        false,
        signers[0].address,
        signers[0].address,
        start,
        expiration
      );
      // track the vault balance before conversion
      const vaultBalance = await token.balanceOf(vault.address);
      await yieldAdapter.convertYT(id, convertAmount, signers[0].address, true);
      // check that yt balance decreased for ID
      const ytBalance = await yieldAdapter.balanceOf(id, signers[0].address);
      expect(ytBalance).to.be.equal(1e4 - convertAmount);
      // vault balance should be the same since no withdrawal
      const newBalance = await token.balanceOf(vault.address);
      expect(vaultBalance).to.be.equal(newBalance);
      // check PT balance?
    });
  });

  it("successful compound conversion after time passes", async () => {
    const convertAmount = 2e2;
    const start = await getCurrentTimestamp(provider);
    const expiration = start + ONE_YEAR_IN_SECONDS;
    const id = getTokenId(start, expiration);

    // create a term by locking some tokens
    await yieldAdapter.lock(
      [],
      [],
      1e4,
      false,
      signers[0].address,
      signers[0].address,
      start,
      expiration
    );

    // advance time
    await advanceTime(provider, SIX_MONTHS_IN_SECONDS);

    // track the vault balance before conversion
    const vaultBalance = await token.balanceOf(vault.address);
    // execute the conversion
    await yieldAdapter.convertYT(id, convertAmount, signers[0].address, true);
    // check that yt balance decreased for the ID
    const ytBalance = await yieldAdapter.balanceOf(id, signers[0].address);
    expect(ytBalance).to.be.equal(1e4 - convertAmount);
    // vault balance should be the same since no withdrawal
    const newBalance = await token.balanceOf(vault.address);
    expect(vaultBalance).to.be.equal(newBalance);
  });
});
