import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { MockYieldAdapter } from "typechain/MockYieldAdapter";
import { MockERC20YearnVault } from "typechain/MockERC20YearnVault";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import { TestERC20 } from "typechain/TestERC20";
import { ForwarderFactory } from "typechain/ForwarderFactory";

const { provider } = waffle;

describe("Deposit Tests", async () => {
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

    // mint some tokens
    await token.mint(signers[0].address, 7e6);
    // set an allowance
    await token.connect(signers[0]).approve(yieldAdapter.address, 12e6);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe.only("Lock", async () => {
    it("empty arrays, only underlying", async () => {
      const now = Math.floor(Date.now() / 1000);
      const expiration = now + 2629800;
      console.log("done");
      const tokensCreated = await yieldAdapter.lock(
        [],
        [],
        5,
        signers[0].address,
        signers[0].address,
        now,
        expiration
      );
    });
  });
});
