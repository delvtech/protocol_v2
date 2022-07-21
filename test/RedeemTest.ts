import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { exp } from "mathjs";
import {
  ForwarderFactory,
  MockERC20YearnVault,
  MockYieldAdapter,
  TestERC20,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import {
  getCurrentTimestamp,
  advanceTime,
  ONE_YEAR_IN_SECONDS,
  SIX_MONTHS_IN_SECONDS,
} from "./helpers/time";
import { BigNumber } from "ethers";
import { getTokenId } from "./helpers/tokenIds";

const { provider } = waffle;

describe.only("Redeem tests", async () => {
  let signers: SignerWithAddress[];
  let factory: ForwarderFactory;
  let token: TestERC20;
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

  it("Fails for assets with different expirations", async () => {
    const start = await getCurrentTimestamp(provider);
    const ytExpiry = start + ONE_YEAR_IN_SECONDS;
    const ytId = getTokenId(start, ytExpiry);
    const ptId = BigNumber.from(start + SIX_MONTHS_IN_SECONDS);
    const tx = await yieldAdapter.connect(signers[0]).redeem(ytId, ptId, 1e3);
    expect(tx).to.be.revertedWith("tokens from different terms");
  });

  it("Fails when sender isn't authorized", async () => {
    const start = await getCurrentTimestamp(provider);
    const expiry = start + ONE_YEAR_IN_SECONDS;
    const ytId = getTokenId(start, expiry);
    const ptId = BigNumber.from(expiry);
    const tx = yieldAdapter.connect(signers[1]).redeem(ytId, ptId, 1e3);
    await expect(tx).to.be.revertedWith("Sender not Authorized");
  });

  it.only("Fails if no term exists for inputs", async () => {
    const start = await getCurrentTimestamp(provider);
    const expiry = start + ONE_YEAR_IN_SECONDS;
    const ytId = getTokenId(start, expiry);
    const ptId = BigNumber.from(expiry);
    const tx = yieldAdapter.redeem(ytId, ptId, 1e3);
    await expect(tx).to.be.revertedWith("Division or modulo division by zero");
  });

  it.only("Fails to redeem more than available", async () => {
    const start = await getCurrentTimestamp(provider);
    const expiry = start + ONE_YEAR_IN_SECONDS;
    const ytId = getTokenId(start, expiry);
    const ptId = BigNumber.from(expiry);

    // create a term by locking some tokens
    await yieldAdapter
      .connect(signers[0])
      .lock([], [], 1e4, signers[0].address, signers[0].address, start, expiry);

    // redeem more than available
    const tx = yieldAdapter.connect(signers[0]).redeem(ytId, ptId, 1e6);
    await expect(tx).to.be.revertedWith(
      "Arithmetic operation underflowed or overflowed outside of an unchecked block"
    );
  });

  it.only("Successfully lock() then redeem()", async () => {
    const start = await getCurrentTimestamp(provider);
    const expiry = start + ONE_YEAR_IN_SECONDS;
    const ytId = getTokenId(start, expiry);
    const ptId = BigNumber.from(expiry);

    // create a term by locking some tokens
    await yieldAdapter.lock(
      [],
      [],
      1e4,
      signers[0].address,
      signers[0].address,
      start,
      expiry
    );
    // track the vault balance before redeem
    const vaultBalance = await token.balanceOf(vault.address);
    // execute the redeem
    await yieldAdapter.redeem(ytId, ptId, 1e3);
    // check that vault balance decreased
    const newBalance = await token.balanceOf(vault.address);
    expect(newBalance).to.be.equal(vaultBalance.toNumber() - 1e3); // unsure of this +1 here
  });

  //TODO: This is not working properly
  it.only("Successfully lock() then redeem() in 6 months", async () => {
    const start = await getCurrentTimestamp(provider);
    const expiry = start + ONE_YEAR_IN_SECONDS;
    const ytId = getTokenId(start, expiry);
    const ptId = BigNumber.from(expiry);

    // create a term by locking some tokens
    await yieldAdapter.lock(
      [],
      [],
      1e4,
      signers[0].address,
      signers[0].address,
      start,
      expiry
    );
    const sharePriceBefore = await yieldAdapter.lockedSharePrice();
    //console.log(sharePriceBefore.toNumber());
    // advance time
    await advanceTime(provider, SIX_MONTHS_IN_SECONDS);
    const sharePriceAfter = await yieldAdapter.lockedSharePrice();
    //console.log(sharePriceAfter.toNumber());
    // track the vault balance before redeem
    const vaultBalance = await token.balanceOf(vault.address);
    // execute the redeem
    await yieldAdapter.redeem(ytId, ptId, 1e3);
    // check that vault balance decreased
    const newBalance = await token.balanceOf(vault.address);
    expect(newBalance).to.be.equal(vaultBalance.toNumber() - 1e3); // unsure of this +1 here
  });
});
