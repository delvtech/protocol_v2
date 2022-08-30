import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers, waffle } from "hardhat";
import { HOUR, MAX_UINT256, WEEK, YEAR, ZERO } from "test/helpers/constants";
import { $ether, now } from "test/helpers/utils";
import {
  ERC4626Term,
  ERC4626Term__factory,
  ForwarderFactory__factory,
  MockERC20,
  MockERC20__factory,
  MockERC4626,
  MockERC4626__factory,
} from "typechain-types";
import { createSnapshot, restoreSnapshot } from "./helpers/snapshots";
import {
  mine,
  stopMining,
  startMining,
  nowBlock,
  setTime,
  setTimeAndMine,
} from "./helpers/bug";
import {
  getTokenId
} from "./helpers/tokenIds";

const { provider } = waffle;

const MAX_RESERVE = $ether(50_000);
const TARGET_RESERVE = $ether(25_000);
const VAULT_SHARE_PRICE = $ether(0.9);

describe("ERC4626Term Complex", () => {
  let token: MockERC20;
  let vault: MockERC4626;
  let term: ERC4626Term;

  let deployer: SignerWithAddress;
  let user: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;

  let UNLOCKED_YT_ID: BigNumber;

  before(async () => {
    [deployer, user, user2, user3] = await ethers.getSigners();

    // deploy token
    token = await new MockERC20__factory()
      .connect(deployer)
      .deploy("MockERC20Token", "MET", 18);

    // deploy vault
    vault = await new MockERC4626__factory()
      .connect(deployer)
      .deploy(token.address);

    const forwaderFactory = await new ForwarderFactory__factory()
      .connect(deployer)
      .deploy();

    const linkCodeHash = await forwaderFactory.ERC20LINK_HASH();
    // deploy term
    term = await new ERC4626Term__factory()
      .connect(deployer)
      .deploy(
        vault.address,
        linkCodeHash,
        forwaderFactory.address,
        MAX_RESERVE,
        deployer.address
      );

    await token.connect(deployer).mint(deployer.address, $ether(4_000));
    await token.connect(deployer).mint(user.address, $ether(1_000));
    await token.connect(deployer).mint(user2.address, $ether(1_000));
    await token.connect(deployer).mint(user3.address, $ether(1_000));
    await token.connect(deployer).approve(vault.address, MAX_UINT256);
    await token.connect(user).approve(term.address, MAX_UINT256);
    await token.connect(user2).approve(term.address, MAX_UINT256);
    await token.connect(user3).approve(term.address, MAX_UINT256);
    await vault.connect(deployer).deposit($ether(2_000), deployer.address);
    await token.connect(deployer).transfer(vault.address, $ether(2_000));
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("Complex cases", () => {
    it.only("BUG", async () => {
      const termStart = 1911772800;
      const termEnd = termStart + 100_000;
      const termId = getTokenId(termStart, termEnd);
      await stopMining(provider);
      await setTime(provider, termStart);
      await term.connect(user)
        .lock(
          [],
          [],
          $ether(1_000),
          false,
          user.address,
          user.address,
          termStart,
          termEnd
        );
      await token.connect(deployer).mint(vault.address, $ether(1_000));
      await term.connect(user2)
        .lock(
          [],
          [],
          $ether(1_000),
          false,
          user2.address,
          user2.address,
          termStart,
          termEnd
        );
      await mine(provider);
      await setTime(provider, termStart + 10_000);
      await token.connect(deployer).mint(vault.address, $ether(1_000));
      await mine(provider);
      await setTime(provider, termStart + 20_000);
      await term.connect(user3)
        .lock(
          [],
          [],
          $ether(1_000),
          false,
          user3.address,
          user3.address,
          termStart,
          termEnd
        );
      await mine(provider);
      console.log('Vault:');
      console.log(await vault.totalSupply());
      console.log(await token.balanceOf(vault.address));
      console.log('User 1:');
      console.log(await token.balanceOf(user.address));
      console.log(await term.balanceOf(termId, user.address));
      console.log(await term.balanceOf(termEnd, user.address));
      console.log('User 2:');
      console.log(await token.balanceOf(user2.address));
      console.log(await term.balanceOf(termId, user2.address));
      console.log(await term.balanceOf(termEnd, user2.address));
      console.log('User 3:');
      console.log(await token.balanceOf(user3.address));
      console.log(await term.balanceOf(termId, user3.address));
      console.log(await term.balanceOf(termEnd, user3.address));
      await setTimeAndMine(provider, termEnd);
      console.log('Unlock 1');
      await term.connect(user)
        .unlock(
          user.address,
          [termId],
          [$ether(1_000)],
        );
      await term.connect(user)
        .unlock(
          user.address,
          [termEnd],
          [$ether(1_000)],
        );
      console.log('Unlock 2');
      await term.connect(user2)
        .unlock(
          user2.address,
          [termId],
          [$ether(1_000)],
        );
      await term.connect(user2)
        .unlock(
          user2.address,
          [termEnd],
          [$ether(1_000)],
        );
      console.log('Unlock 3');
      await term.connect(user3)
        .unlock(
          user3.address,
          [termId],
          [$ether(1_000)],
        );
      await term.connect(user3)
        .unlock(
          user3.address,
          [termEnd],
          [await term.balanceOf(termEnd, user3.address)],
        );
      console.log('Vault:');
      console.log(await vault.totalSupply());
      console.log(await token.balanceOf(vault.address));
      console.log('User 1:');
      console.log(await token.balanceOf(user.address));
      console.log(await term.balanceOf(termId, user.address));
      console.log(await term.balanceOf(termEnd, user.address));
      console.log('User 2:');
      console.log(await token.balanceOf(user2.address));
      console.log(await term.balanceOf(termId, user2.address));
      console.log(await term.balanceOf(termEnd, user2.address));
      console.log('User 3:');
      console.log(await token.balanceOf(user3.address));
      console.log(await term.balanceOf(termId, user3.address));
      console.log(await term.balanceOf(termEnd, user3.address));
    });
  });
});
