import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { ONE_THOUSAND_ETHER } from "test/helpers/constants";
import {
  ERC20,
  ERC20__factory,
  ERC4626YieldAdapter,
  ERC4626YieldAdapter__factory,
  MockERC4626,
  MockERC4626__factory,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "../helpers/snapshots";

const { provider } = waffle;

describe("ERC4626YieldAdapter", async () => {
  let token: ERC20;
  let vault: MockERC4626;
  let adapter: ERC4626YieldAdapter;

  let deployer: SignerWithAddress;
  let user: SignerWithAddress;

  before(async () => {
    [deployer, user] = await ethers.getSigners();
    token = await new ERC20__factory()
      .connect(deployer)
      .deploy("MockERC20Token", "MET");

    vault = await new MockERC4626__factory()
      .connect(deployer)
      .deploy(token.address);

    adapter = await new ERC4626YieldAdapter__factory()
      .connect(deployer)
      .deploy(vault.address, ONE_THOUSAND_ETHER);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("deployment", async () => {
    it("jjb", () => {
      expect(5).to.be.eq(5);
    });
  });

  // describe("_deposit", async () => {
  //   return;
  // });

  // describe("_withdraw", async () => {
  //   return;
  // });

  // describe("_convert", async () => {
  //   return;
  // });

  // describe("_underlying", async () => {
  //   return;
  // });
});
