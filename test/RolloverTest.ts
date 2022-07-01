import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { MockYieldAdapter } from "typechain/MockYieldAdapter";
import { MockERC20YearnVault } from "typechain/MockERC20YearnVault";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { TestERC20 } from "typechain/TestERC20";
import { ForwarderFactory } from "typechain/ForwarderFactory";
import { advanceBlock, advanceTime, getCurrentTimestamp } from "./helpers/time";

const { provider } = waffle;

describe("Rollover Tests", async () => {
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

    // make deposits into an account
    const start = await getCurrentTimestamp(provider);
    const expiration = start + SECONDS_IN_YEAR * 3;
    await yieldAdapter.lock(
        [],
        [],
        5,
        signers[0].address,
        signers[0].address,
        start,
        expiration
      );
    advanceTime(provider, SECONDS_IN_YEAR);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  it("Successful rollover", async () => {

  });
  it("Rollover and add underlying", async () => {
    const start = await getCurrentTimestamp(provider);
    const expiration = start + SECONDS_IN_YEAR * 3;
    await yieldAdapter.lock(
        [], // TODO: id's
        [], // amounts
        1e3,
        signers[0].address,
        signers[0].address,
        start,
        expiration
    );
  });
});
