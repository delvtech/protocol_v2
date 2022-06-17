import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { MAX_UINT256, ONE_ETHER, ZERO } from "test/helpers/constants";
import {
  MockERC20,
  MockERC20__factory,
  MockERC4626,
  MockERC4626__factory,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "../helpers/snapshots";

const { provider } = waffle;

describe.only("MockERC4626", async () => {
  let token: MockERC20;
  let vault: MockERC4626;

  let deployer: SignerWithAddress;
  let user: SignerWithAddress;

  before(async () => {
    [deployer, user] = await ethers.getSigners();

    vault = await new MockERC4626__factory().connect(deployer).deploy(18);
    const _token = await vault.connect(user).asset();
    token = MockERC20__factory.connect(_token, user);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  it("should issue shares to caller", async () => {
    expect(await vault.totalSupply()).to.be.eq(ZERO);
    expect(await vault.totalAssets()).to.be.eq(ZERO);
    expect(await vault.balanceOf(user.address)).to.be.eq(ZERO);

    await vault.issueShares(user.address, ONE_ETHER);

    expect(await vault.balanceOf(user.address)).to.be.eq(ONE_ETHER);
    expect(await vault.totalSupply()).to.be.eq(ONE_ETHER);
    expect(await vault.totalAssets()).to.be.eq(ZERO);
  });

  it.only("should destroy shares from caller", async () => {
    console.log("jbjbj");
    await token.mint(user.address, ONE_ETHER);

    console.log("jbjbj");
    await token.approve(vault.address, MAX_UINT256);

    console.log(await token.allowance(user.address, vault.address));
    console.log("jbjbj");
    await vault.deposit(ONE_ETHER, user.address);

    console.log("jbjbj");
    expect(await vault.totalSupply()).to.be.eq(ONE_ETHER);
    expect(await vault.totalAssets()).to.be.eq(ONE_ETHER);
    expect(await vault.balanceOf(user.address)).to.be.eq(ONE_ETHER);

    console.log("jbjbj");
    await vault.approve(vault.address, ONE_ETHER);
    await vault.destroyShares(user.address, ONE_ETHER);

    expect(await vault.balanceOf(user.address)).to.be.eq(ZERO);
    expect(await vault.totalSupply()).to.be.eq(ZERO);
    expect(await vault.totalAssets()).to.be.eq(ONE_ETHER);
  });
});
