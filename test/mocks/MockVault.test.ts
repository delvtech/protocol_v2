import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { mine, YEAR } from "test/helpers/time";
import {
  MockAsset,
  MockAsset__factory,
  MockVault,
  MockVault__factory,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "../helpers/snapshots";
import {
  MOCK_ASSET_TOKEN_NAME,
  MOCK_ASSET_TOKEN_SYMBOL,
} from "./MockAsset.test";

const { provider } = waffle;

export const MOCK_SHARE_TOKEN_NAME = "MockShareToken";
export const MOCK_SHARE_TOKEN_SYMBOL = "xMAT";

const ONE_MILLION_ETHER = ethers.utils.parseEther("1000000");
const TEN_THOUSAND_ETHER = ethers.utils.parseEther("10000");

describe("MockVault", async () => {
  let asset: MockAsset;
  let vault: MockVault;
  let owner: SignerWithAddress;

  let user: SignerWithAddress;
  before(async () => {
    [owner, user] = await ethers.getSigners();

    vault = await new MockVault__factory().connect(owner).deploy(user.address);

    vault = vault.connect(user);
    const _asset = await vault.asset();
    asset = MockAsset__factory.connect(_asset, user);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("deployment", async () => {
    it("should initialise $xMAT", async () => {
      const name = await vault.name();
      const symbol = await vault.symbol();
      const decimals = await vault.decimals();

      expect(name).to.be.eq(MOCK_SHARE_TOKEN_NAME);
      expect(symbol).to.be.eq(MOCK_SHARE_TOKEN_SYMBOL);
      expect(decimals).to.be.eq(18);
    });

    it("should deploy $MAT", async () => {
      const name = await asset.name();
      const symbol = await asset.symbol();
      const decimals = await asset.decimals();

      expect(name).to.be.eq(MOCK_ASSET_TOKEN_NAME);
      expect(symbol).to.be.eq(MOCK_ASSET_TOKEN_SYMBOL);
      expect(decimals).to.be.eq(18);
    });

    it("should initialise $MAT with correct supply", async () => {
      const totalSupply = await asset.totalSupply();
      expect(totalSupply).to.be.eq(ONE_MILLION_ETHER);
    });

    it("should mint initial $MAT supply to specified receiver", async () => {
      const balance = await asset.balanceOf(user.address);
      expect(balance).to.be.eq(ONE_MILLION_ETHER);
    });

    it("should set correct owner for both $MAT and vault contracts", async () => {
      const assetOwner = await asset.owner();
      const vaultOwner = await vault.owner();
      expect(assetOwner).to.be.eq(vault.address);
      expect(vaultOwner).to.be.eq(owner.address);
    });

    it(`should have 0 assets deposited and 0 shares issued`, async () => {
      const totalAssets = await vault.totalAssets();
      const totalShares = await vault.totalSupply();

      expect(totalAssets).to.be.eq(ethers.constants.Zero);
      expect(totalShares).to.be.eq(ethers.constants.Zero);
    });

    it(`should initially price assets:shares as 1:1`, async () => {
      const sharesPerAsset = await vault.convertToShares(ethers.constants.One);
      const assetsPerShare = await vault.convertToAssets(ethers.constants.One);

      expect(sharesPerAsset).to.be.eq(ethers.constants.One);
      expect(assetsPerShare).to.be.eq(ethers.constants.One);
    });

    it(`should initialise interest rates correctly`, async () => {
      const apr = await vault.apr();
      const apy = await vault.apy();

      expect(apr).to.be.eq(ethers.utils.parseEther("0.05")); // 5%
      expect(apy).to.be.eq(ethers.utils.parseEther("0.051271096350458156")); // 5.1271096350458156 %
    });
  });

  // describe.only("deposit", async () => {
  //   const depositAmount = ethers.utils.parseEther("1");

  //   it("should revert depositing if vault is not collateralized", async () => {
  //     //await asset.connect(user).approve(vault.address, depositAmount);

  //     const tx = await vault.connect(user).deposit(depositAmount, user.address);
  //     expect(tx).to.be.revertedWith();
  //   });
  // });

  //it("should approve asset with vault address")

  // describe("accrue", async () => {
  //   const depositAmount = ethers.utils.parseEther("1");

  //   before(async () => {
  //     await asset.connect(user.address).approve(vault.address, depositAmount);
  //     await vault.connect(user.address).deposit(depositAmount, user.address);
  //   });

  //   it(`should have ${ethers.utils.formatEther(
  //     depositAmount
  //   )} assets deposited and ${ethers.utils.formatEther(
  //     depositAmount
  //   )} shares issued`, async () => {
  //     const totalAssets = await vault.totalAssets();
  //     const totalShares = await vault.totalSupply();

  //     expect(totalAssets).to.be.eq(depositAmount);
  //     expect(totalShares).to.be.eq(depositAmount);
  //   });

  //   it("should accrue interest correctly", async () => {
  //     const currentBlock = await ethers.provider.getBlock("latest");
  //     console.log(currentBlock);
  //     const x = await mine(YEAR);
  //     // console.log(x.previous, x.latest, x.interval);
  //     // await vault.accrue();

  //     // const totalAssets = await vault.totalAssets();
  //     // expect(totalAssets).to.be.eq(depositAmount.add("0.051271096350458156"));
  //   });
  // });
});
