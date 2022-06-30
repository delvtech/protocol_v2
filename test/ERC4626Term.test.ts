import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, ContractReceipt } from "ethers";
import { ethers, waffle } from "hardhat";
import { HOUR, MAX_UINT256, YEAR, ZERO } from "test/helpers/constants";
import { $ether, now, printEther } from "test/helpers/utils";
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

const { provider } = waffle;

// TEST two deposits and two withdraws in one block
// Refactor to use lock/unlock
//
const MAX_RESERVE = $ether("50000");
const TARGET_RESERVE = $ether("25000");
const VAULT_SHARE_PRICE = $ether("0.9");

const TERM_START = now() + HOUR; // we tack on an hour so that ytBeginDate defaults to blockTimestamp
const TERM_END = TERM_START + YEAR; // This becomes the ID

describe.only("ERC4626Term", () => {
  let token: MockERC20;
  let vault: MockERC4626;
  let term: ERC4626Term;

  let deployer: SignerWithAddress;
  let user: SignerWithAddress;

  let UNLOCKED_YT_ID: BigNumber;

  before(async () => {
    [deployer, user] = await ethers.getSigners();

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
        MAX_RESERVE
      );

    // get ID to track share total supply
    UNLOCKED_YT_ID = await term.UNLOCKED_YT_ID();

    // set price ratio of vaultShares and underlying
    await token.connect(deployer).mint(deployer.address, $ether("10000"));
    await token.connect(deployer).approve(vault.address, MAX_UINT256);
    await vault.connect(deployer).deposit($ether("9000"), deployer.address);
    await token.connect(deployer).transfer(vault.address, $ether("1000"));

    // mint and set approvals for user on term
    await token.mint(user.address, $ether("1000000"));
    await token.connect(user).approve(term.address, MAX_UINT256);
  });

  beforeEach(async () => {
    await createSnapshot(provider);
  });

  afterEach(async () => {
    await restoreSnapshot(provider);
  });

  describe("deployment", () => {
    it("term", async () => {
      expect(await term.vault()).to.be.eq(vault.address);
      expect(await term.underlyingReserve()).to.be.eq(ZERO);
      expect(await term.vaultShareReserve()).to.be.eq(ZERO);
      expect(await term.targetReserve()).to.be.eq(TARGET_RESERVE);
      expect(await term.maxReserve()).to.be.eq(MAX_RESERVE);
      expect(await term.totalSupply(UNLOCKED_YT_ID)).to.be.eq(ZERO);

      expect(await token.balanceOf(term.address)).to.be.eq(ZERO);
      expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
    });

    it("vault", async () => {
      expect(await vault.totalAssets()).to.be.eq($ether("10000"));
      expect(await vault.totalSupply()).to.be.eq($ether("9000"));
      expect(await vault.previewDeposit($ether("1"))).to.be.eq(
        VAULT_SHARE_PRICE
      );
    });
  });

  describe("ShareState.Unlocked", () => {
    describe("_deposit", () => {
      let initialTotalSupply: BigNumber;
      describe("underlyingReserve === 0", () => {
        beforeEach(async () => {
          initialTotalSupply = await term.totalSupply(UNLOCKED_YT_ID);
        });

        it("initial state", async () => {
          // token balances, reserves and shares issued should be zero
          expect(await term.underlyingReserve()).to.be.eq(ZERO);
          expect(await token.balanceOf(term.address)).to.be.eq(ZERO);
          expect(await term.vaultShareReserve()).to.be.eq(ZERO);
          expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
          expect(initialTotalSupply).to.be.eq(ZERO);
        });

        it("should issue shares without depositing to the vault when underlying deposited + reserve is BELOW the max reserve", async () => {
          // tx
          const receipt = await (
            await term
              .connect(user)
              .lock(
                [],
                [],
                $ether("1000"),
                user.address,
                user.address,
                TERM_START,
                0
              )
          ).wait(1);
          expect(receipt.status).to.be.eq(1);
          const sharesIssued = (await term.totalSupply(UNLOCKED_YT_ID)).sub(
            initialTotalSupply
          );
          // As it is the initial deposit, shares issued should match amount of
          // underlying deposited 1:1
          expect(sharesIssued).to.be.eq($ether("1000"));

          // As the underlying amount the user deposited plus the existing
          // underlying reserve is less than the max reserve, no deposit into the
          // vault should occur
          const vaultDepositEvents = await vault.queryFilter(
            vault.filters.Deposit(user.address),
            receipt.blockHash
          );
          expect(vaultDepositEvents).to.be.empty;

          // reserves and term token balances
          expect(await term.underlyingReserve()).to.be.eq($ether("1000"));
          expect(await token.balanceOf(term.address)).to.be.eq($ether("1000"));
          expect(await term.vaultShareReserve()).to.be.eq(ZERO);
          expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
        });

        it("should issue shares, depositing underlying to the vault when underlying deposited + reserve is ABOVE the max reserve", async () => {
          // tx
          const receipt = await (
            await term
              .connect(user)
              .lock(
                [],
                [],
                $ether("100000"),
                user.address,
                user.address,
                TERM_START,
                0
              )
          ).wait(1);
          expect(receipt.status).to.be.eq(1);

          const sharesIssued = (await term.totalSupply(UNLOCKED_YT_ID)).sub(
            initialTotalSupply
          );
          // As it is the initial deposit, shares issued should match amount of
          // underlying deposited 1:1
          expect(sharesIssued).to.be.eq($ether("100000"));

          // As the underlying amount the user deposited plus the existing
          // underlying reserve is greater than the max reserve, an amount of
          // underlying is siphoned to meet the targetReserve and the rest is
          // deposited into the vault, exchanged for an amount of vaultShares
          const vaultDepositEvents = await vault.queryFilter(
            vault.filters.Deposit(),
            receipt.blockHash
          );
          expect(vaultDepositEvents).to.not.be.empty;
          const [
            {
              args: {
                assets: underlyingDepositedToVault,
                shares: vaultShares,
                caller,
              },
            },
          ] = vaultDepositEvents;
          expect(caller).to.be.eq(term.address);

          expect(underlyingDepositedToVault).to.be.eq($ether("75000"));

          const expectedVaultShares = $ether("75000")
            .mul(VAULT_SHARE_PRICE)
            .div($ether("1"));
          expect(vaultShares).to.be.eq(expectedVaultShares);

          // reserves and term token balances
          expect(await term.underlyingReserve()).to.be.eq(TARGET_RESERVE);
          expect(await token.balanceOf(term.address)).to.be.eq(TARGET_RESERVE);
          expect(await term.vaultShareReserve()).to.be.eq(expectedVaultShares);
          expect(await vault.balanceOf(term.address)).to.be.eq(
            expectedVaultShares
          );
        });
      });

      describe("underlyingReserve < targetReserve", () => {
        beforeEach(async () => {
          await term
            .connect(user)
            .lock(
              [],
              [],
              $ether("10000"),
              user.address,
              user.address,
              TERM_START,
              0
            );

          initialTotalSupply = await term.totalSupply(UNLOCKED_YT_ID);
        });

        it("initial state", async () => {
          // token balances, reserves and shares issued should be as expected
          expect(await term.underlyingReserve()).to.be.eq($ether("10000"));
          expect(await token.balanceOf(term.address)).to.be.eq($ether("10000"));
          expect(await term.vaultShareReserve()).to.be.eq(ZERO);
          expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
          expect(await term.totalSupply(UNLOCKED_YT_ID)).to.be.eq(
            $ether("10000")
          );
        });

        it("should issue shares without depositing to the vault when underlying deposited + reserve is BELOW the max reserve", async () => {
          // tx
          const receipt = await (
            await term
              .connect(user)
              .lock(
                [],
                [],
                $ether("1000"),
                user.address,
                user.address,
                TERM_START,
                0
              )
          ).wait(1);
          expect(receipt.status).to.be.eq(1);

          // share totalSupply differential
          const sharesIssued = (await term.totalSupply(UNLOCKED_YT_ID)).sub(
            initialTotalSupply
          );
          // As no interest has been accounted for in the vault since the
          // deployment of the term, we can expect shares to be priced 1:1
          // with underlying
          expect(sharesIssued).to.be.eq($ether("1000"));

          // no vault deposit event should occur
          const vaultDepositEvents = await vault.queryFilter(
            vault.filters.Deposit(user.address),
            receipt.blockHash
          );
          expect(vaultDepositEvents).to.be.empty;

          // underlying deposited should be added to the reserve
          expect(await term.underlyingReserve()).to.be.eq($ether("11000"));

          // underlying token balance should reflect reserve
          expect(await token.balanceOf(term.address)).to.be.eq($ether("11000"));

          // vaultShare reserve should be unchanged from initial state
          expect(await term.vaultShareReserve()).to.be.eq(ZERO);
          // as only unlocked deposits, vaultShare token balance should match reserve
          expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
        });

        it("should issue shares, depositing to the vault when underlying deposited + reserve is ABOVE the max reserve", async () => {
          // tx
          const receipt = await (
            await term
              .connect(user)
              .lock(
                [],
                [],
                $ether("100000"),
                user.address,
                user.address,
                TERM_START,
                0
              )
          ).wait(1);
          expect(receipt.status).to.be.eq(1);

          // share totalSupply differential
          const sharesIssued = (await term.totalSupply(UNLOCKED_YT_ID)).sub(
            initialTotalSupply
          );

          // As no interest has been accounted for in the vault since the
          // deployment of the term, we can expect shares to be priced 1:1
          // with underlying
          expect(sharesIssued).to.be.eq($ether("100000"));

          const vaultDepositEvents = await vault.queryFilter(
            vault.filters.Deposit(),
            receipt.blockHash
          );
          // should be a deposit event
          expect(vaultDepositEvents).to.not.be.empty;

          const [
            {
              args: {
                assets: underlyingDepositedToVault,
                shares: vaultShares,
                caller,
              },
            },
          ] = vaultDepositEvents;

          // As the initial underlyingReserve was 10K and the user deposited
          // 100K, the contract will maintain a targetReserve of 25K when the
          // max is exceeded meaning (110K - 25K) 85K is deposited into the
          // vault @ 0.9 vaultShares per underlying, giving 76.5K vaultShares
          expect(caller).to.be.eq(term.address);
          expect(underlyingDepositedToVault).to.be.eq($ether("85000"));
          expect(vaultShares).to.be.eq($ether("76500"));

          // As the combined amount of underlyingReserve and underlying
          // deposited was above the maxReserve, the reserve and balance of
          // underlying should be at the target reserve
          expect(await term.underlyingReserve()).to.be.eq(TARGET_RESERVE);
          expect(await token.balanceOf(term.address)).to.be.eq(TARGET_RESERVE);

          // When the term contract deposits to the vault it gets vaultShares
          // back and accrues those vaultShares in the reserve
          expect(await term.vaultShareReserve()).to.be.eq($ether("76500"));
          expect(await vault.balanceOf(term.address)).to.be.eq($ether("76500"));
        });
      });

      describe("underlyingReserve === targetReserve", () => {
        beforeEach(async () => {
          await term
            .connect(user)
            .lock(
              [],
              [],
              $ether("525000"),
              user.address,
              user.address,
              TERM_START,
              0
            );

          initialTotalSupply = await term.totalSupply(UNLOCKED_YT_ID);
        });

        it("initial state", async () => {
          // token balances, reserves and shares issued should be as expected
          expect(await term.underlyingReserve()).to.be.eq(TARGET_RESERVE);
          expect(await token.balanceOf(term.address)).to.be.eq(TARGET_RESERVE);
          expect(await term.vaultShareReserve()).to.be.eq($ether("450000"));
          expect(await vault.balanceOf(term.address)).to.be.eq(
            $ether("450000")
          );
          expect(await term.totalSupply(UNLOCKED_YT_ID)).to.be.eq(
            $ether("525000")
          );
        });

        it("should issue shares without depositing to the vault when underlying deposited + reserve is BELOW the max reserve", async () => {
          // tx
          const receipt = await (
            await term
              .connect(user)
              .lock(
                [],
                [],
                $ether("1000"),
                user.address,
                user.address,
                TERM_START,
                0
              )
          ).wait(1);
          expect(receipt.status).to.be.eq(1);

          // share totalSupply differential
          const sharesIssued = (await term.totalSupply(UNLOCKED_YT_ID)).sub(
            initialTotalSupply
          );
          // As no interest has been accounted for in the vault since the
          // deployment of the term, we can expect shares to be priced 1:1
          // with underlying
          expect(sharesIssued).to.be.eq($ether("1000"));

          // no vault deposit event should occur
          const vaultDepositEvents = await vault.queryFilter(
            vault.filters.Deposit(user.address),
            receipt.blockHash
          );
          expect(vaultDepositEvents).to.be.empty;

          // underlying deposited should be added to the reserve
          expect(await term.underlyingReserve()).to.be.eq($ether("26000"));

          // underlying token balance should reflect reserve
          expect(await token.balanceOf(term.address)).to.be.eq($ether("26000"));

          // vaultShare reserve should be unchanged from initial state
          expect(await term.vaultShareReserve()).to.be.eq($ether("450000"));

          // as only unlocked deposits, vaultShare token balance should match reserve
          expect(await vault.balanceOf(term.address)).to.be.eq(
            $ether("450000")
          );
        });

        it("should issue shares, depositing to the vault when underlying deposited + reserve is ABOVE the max reserve", async () => {
          // tx
          const receipt = await (
            await term
              .connect(user)
              .lock(
                [],
                [],
                $ether("50000"),
                user.address,
                user.address,
                TERM_START,
                0
              )
          ).wait(1);
          expect(receipt.status).to.be.eq(1);

          // share totalSupply differential
          const sharesIssued = (await term.totalSupply(UNLOCKED_YT_ID)).sub(
            initialTotalSupply
          );

          // As no interest has been accounted for in the vault since the
          // deployment of the term, we can expect shares to be priced 1:1
          // with underlying
          expect(sharesIssued).to.be.eq($ether("50000"));

          const vaultDepositEvents = await vault.queryFilter(
            vault.filters.Deposit(),
            receipt.blockHash
          );
          // should be a deposit event
          expect(vaultDepositEvents).to.not.be.empty;

          const [
            {
              args: {
                assets: underlyingDepositedToVault,
                shares: vaultShares,
                caller,
              },
            },
          ] = vaultDepositEvents;

          // As the initial underlyingReserve was 25K and the user deposited
          // 50K, we wish to maintain the targetReserve so 50K is deposited
          // into the vault @ 0.9 vaultShares per underlying, giving 45K
          // vaultShares
          expect(caller).to.be.eq(term.address);
          expect(underlyingDepositedToVault).to.be.eq($ether("50000"));
          expect(vaultShares).to.be.eq($ether("45000"));

          // As the combined amount of underlyingReserve and underlying
          // deposited was above the maxReserve, the reserve and balance of
          // underlying should be at the target reserve
          expect(await term.underlyingReserve()).to.be.eq(TARGET_RESERVE);
          expect(await token.balanceOf(term.address)).to.be.eq(TARGET_RESERVE);

          // When the term contract deposits to the vault it gets vaultShares
          // back and accrues those vaultShares in the reserve
          expect(await term.vaultShareReserve()).to.be.eq($ether("495000"));
          expect(await vault.balanceOf(term.address)).to.be.eq(
            $ether("495000")
          );
        });
      });

      describe("underlyingReserve > targetReserve && underlyingReserve < maxReserve", () => {
        beforeEach(async () => {
          await term
            .connect(user)
            .lock(
              [],
              [],
              $ether("40000"),
              user.address,
              user.address,
              TERM_START,
              0
            );

          initialTotalSupply = await term.totalSupply(UNLOCKED_YT_ID);
        });
        it("initial state", async () => {
          // token balances, reserves and shares issued should be as expected
          expect(await term.underlyingReserve()).to.be.eq($ether("40000"));
          expect(await token.balanceOf(term.address)).to.be.eq($ether("40000"));
          expect(await term.vaultShareReserve()).to.be.eq(ZERO);
          expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
          expect(await term.totalSupply(UNLOCKED_YT_ID)).to.be.eq(
            $ether("40000")
          );
        });

        it("should issue shares without depositing to the vault when underlying deposited + reserve is BELOW the max reserve", async () => {
          // tx
          const receipt = await (
            await term
              .connect(user)
              .lock(
                [],
                [],
                $ether("1000"),
                user.address,
                user.address,
                TERM_START,
                0
              )
          ).wait(1);
          expect(receipt.status).to.be.eq(1);

          // share totalSupply differential
          const sharesIssued = (await term.totalSupply(UNLOCKED_YT_ID)).sub(
            initialTotalSupply
          );
          // As no interest has been accounted for in the vault since the
          // deployment of the term, we can expect shares to be priced 1:1
          // with underlying
          expect(sharesIssued).to.be.eq($ether("1000"));

          // no vault deposit event should occur
          const vaultDepositEvents = await vault.queryFilter(
            vault.filters.Deposit(user.address),
            receipt.blockHash
          );
          expect(vaultDepositEvents).to.be.empty;

          // underlying deposited should be added to the reserve
          expect(await term.underlyingReserve()).to.be.eq($ether("41000"));

          // underlying token balance should reflect reserve
          expect(await token.balanceOf(term.address)).to.be.eq($ether("41000"));

          // vaultShare reserve should be unchanged from initial state
          expect(await term.vaultShareReserve()).to.be.eq(ZERO);
          expect(await vault.balanceOf(term.address)).to.be.eq(ZERO);
        });

        it("should issue shares, depositing to the vault when underlying deposited + reserve is ABOVE the max reserve", async () => {
          // tx
          const receipt = await (
            await term
              .connect(user)
              .lock(
                [],
                [],
                $ether("100000"),
                user.address,
                user.address,
                TERM_START,
                0
              )
          ).wait(1);
          expect(receipt.status).to.be.eq(1);

          // share totalSupply differential
          const sharesIssued = (await term.totalSupply(UNLOCKED_YT_ID)).sub(
            initialTotalSupply
          );

          // As no interest has been accounted for in the vault since the
          // deployment of the term, we can expect shares to be priced 1:1
          // with underlying
          expect(sharesIssued).to.be.eq($ether("100000"));

          const vaultDepositEvents = await vault.queryFilter(
            vault.filters.Deposit(),
            receipt.blockHash
          );
          // should be a deposit event
          expect(vaultDepositEvents).to.not.be.empty;

          const [
            {
              args: {
                assets: underlyingDepositedToVault,
                shares: vaultShares,
                caller,
              },
            },
          ] = vaultDepositEvents;

          // As the initial underlyingReserve was 40K and the user deposited
          // 100K, the contract will maintain a targetReserve of 25K when the
          // max is exceeded meaning (140K - 25K) 115K is deposited into the
          // vault @ 0.9 vaultShares per underlying, giving 103.5K vaultShares
          expect(caller).to.be.eq(term.address);
          expect(underlyingDepositedToVault).to.be.eq($ether("115000"));
          expect(vaultShares).to.be.eq($ether("103500"));

          // As the combined amount of underlyingReserve and underlying
          // deposited was above the maxReserve, the reserve and balance of
          // underlying should be at the target reserve
          expect(await term.underlyingReserve()).to.be.eq(TARGET_RESERVE);
          expect(await token.balanceOf(term.address)).to.be.eq(TARGET_RESERVE);

          // When the term contract deposits to the vault it gets vaultShares
          // back and accrues those vaultShares in the reserve
          expect(await term.vaultShareReserve()).to.be.eq($ether("103500"));
          expect(await vault.balanceOf(term.address)).to.be.eq(
            $ether("103500")
          );
        });

        xdescribe("should exhibit expected behaviour across multiple deposits and accrueing interest", () => {});
      });
    });

    describe.only("_withdraw", () => {
      describe("underlyingReserve > 0", () => {
        beforeEach(async () => {
          // setup state by locking
          await term.connect(user).lock(
            [],
            [],
            $ether("1000000"), // deposit first half of underlying into vault
            user.address,
            user.address,
            TERM_START,
            0
          );

          await term
            .connect(user)
            .setApproval(UNLOCKED_YT_ID, term.address, MAX_UINT256);
        });

        it("initial state", async () => {
          expect(await vault.previewDeposit($ether("1"))).to.be.eq(
            $ether("0.9")
          );

          expect(await token.balanceOf(user.address)).to.be.eq(ZERO);

          // expect underlyingReserve to be at target
          expect(await term.underlyingReserve()).to.be.eq(TARGET_RESERVE);
          expect(await token.balanceOf(term.address)).to.be.eq(TARGET_RESERVE);

          expect(await term.vaultShareReserve()).to.be.eq($ether("877500"));
          expect(await vault.balanceOf(term.address)).to.be.eq(
            $ether("877500")
          );
          expect(await token.balanceOf(user.address)).to.be.eq(ZERO);
          expect(await term.balanceOf(UNLOCKED_YT_ID, user.address)).to.be.eq(
            $ether("1000000")
          );
        });

        it("should withdraw underlying from underlyingReserve if underlyingDue is less than underlyingReserve", async () => {
          // tx
          const receipt = await (
            await term.connect(user).unlock(user.address, [0], [$ether("10")])
          ).wait(1);
          expect(receipt.status).to.be.eq(1);

          const underlyingWithdrawn = await token.balanceOf(user.address);
          expect(underlyingWithdrawn).to.be.eq($ether("10"));
        });
        xit("should withdraw underlying from underlyingReserve if underlyingDue is equal to underlyingReserve", async () => {});
        xit("should withdraw underlying from a redeemed portion of the vaultShareReserve if underlyingDue > underlyingReserve && underlyingDue < underlying value of vaultShareReserve", async () => {});
        xit("should withdraw underlying from all of the vaultShareReserve if underlyingDue > underlyingReserve && underlyingDue === underlying value of vaultShareReserve", async () => {});
        xit("should withdraw underlying from all of the vaultShareReserve with a portion of the underlyingReserve if underlyingDue > underlyingReserve && underlyingDue > underlying value of vaultShareReserve", async () => {});
        xit("should withdraw underlying from all of the vaultShareReserve and all of the underlyingReserve if underlyingDue === underlyingReserve + underlying value of vaultShareReserve", async () => {});
      });
    });

    xdescribe("underlyingReserve === 0", () => {});
  });

  describe("ShareState.Locked", () => {
    describe("_deposit", () => {
      it("should issue shares relative to value of vaultShares issued", async () => {
        const prevSupply = await term.totalSupply(TERM_END);

        // tx
        const receipt = await (
          await term
            .connect(user)
            .lock(
              [],
              [],
              $ether("1000"),
              user.address,
              user.address,
              TERM_START,
              TERM_END
            )
        ).wait(1);
        expect(receipt.status).to.be.eq(1);

        const vaultDepositEvents = await vault.queryFilter(
          vault.filters.Deposit(),
          receipt.blockHash
        );
        expect(vaultDepositEvents).to.not.be.empty;

        const [
          {
            args: { assets: underlyingDepositedToVault, shares: vaultShares },
          },
        ] = vaultDepositEvents;

        const sharesIssued = (await term.totalSupply(TERM_END)).sub(prevSupply);

        expect(underlyingDepositedToVault).to.be.eq($ether("1000"));
        expect(vaultShares).to.be.eq($ether("900"));
        expect(sharesIssued).to.be.eq($ether("1000"));
      });
    });
  });
});
