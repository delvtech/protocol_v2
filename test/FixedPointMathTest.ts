import { ethers } from "hardhat";
import chai, { expect } from "chai";
import chaiAlmost from "chai-almost";
import { MockFixedPointMath } from "typechain-types";
import fp from "evm-fp";
import forEach from "mocha-each";
import { BigNumber as MathjsBigNumber, all, create } from "mathjs";

const config = {
  number: "BigNumber",
  precision: 79,
};

const math = create(all, config)!;
const mbn = math.bignumber!;

function pow(x: string, y: string): string {
  return (<MathjsBigNumber>math.pow!(mbn(x), mbn(y))).toString();
}

function exp(x: string): string {
  return (<MathjsBigNumber>math.exp!(mbn(x))).toString();
}

chai.use(chaiAlmost(1e-5));
describe("FixedPointMath Tests", function () {
  let MockFixedPointMath: MockFixedPointMath;

  before(async () => {
    const factory = await ethers.getContractFactory("MockFixedPointMath");
    MockFixedPointMath = await factory.deploy();
  });

  context("pow()", function () {
    const powTests = [
      ["0", "1"],
      ["1", "0"],
      ["1", "1"],
      ["2", "3"],
      ["4", "0.5"],
      ["0.25", "0.5"],
      ["1e-18", "1e-18"],
      ["1e-12", "4.4e-9"],
      ["0.1", "0.8"],
      ["0.24", "11"],
      ["0.5", "0.7373"],
      ["0.799291", "69"],
      ["1", "0.1"],
      ["11", "28.57142"],
      ["32.15", "0.99"],
      ["406", "0.25"],
      ["1729", "0.98"],
      ["2345.321", "0.0002383475"],
      ["10358673923948475759392", "0.00033928745"],
      ["45683725649", "0.001891"],
      ["340282366920938463463374607431768211455", "0.0021"], // 2^128 - 1
    ];

    describe("Untyped", function () {
      forEach(powTests).it(
        "handles %s^(%s)",
        async function (x: string, y: string) {
          const expected = fp(pow(x, y));
          const result = await MockFixedPointMath.pow(fp(x), fp(y));
          //console.log(Number(ethers.utils.formatEther(result)));
          //console.log(Number(ethers.utils.formatEther(expected)));
          expect(Number(ethers.utils.formatEther(result))).to.be.equal(
            Number(ethers.utils.formatEther(expected))
          );
        }
      );
    });

    describe("Typed", function () {
      forEach(powTests).it(
        "handles %s^(%s)",
        async function (x: string, y: string) {
          const expected = fp(pow(x, y));
          const result = await MockFixedPointMath.powTyped(fp(x), fp(y));
          expect(Number(ethers.utils.formatEther(result))).to.be.equal(
            Number(ethers.utils.formatEther(expected))
          );
        }
      );
    });
  });

  context("exp()", function () {
    const expTests = [
      ["0"],
      ["1"],
      ["130.700829182905140221"], // _MAX_NATURAL_EXPONENT = ln((2^255 - 1) / 10^20)
      ["-41.446531673892822312"], // _MIN_NATURAL_EXPONENT = ln(10^(-18))
    ];

    describe("Untyped", function () {
      forEach(expTests).it("handles e^(%s)", async function (x: string) {
        const expected = fp(exp(x));
        const result = await MockFixedPointMath.exp(fp(x));
        console.log(Number(ethers.utils.formatEther(result)));
        console.log(Number(ethers.utils.formatEther(expected)));
        expect(Number(ethers.utils.formatEther(result))).to.be.equal(
          Number(ethers.utils.formatEther(expected))
        );
      });

      it("Should return zero when floor(log(0.5e18) * 1e18)", async function () {
        const expected = fp("0");
        const x = "-42.139678854452767551";
        const result = await MockFixedPointMath.exp(fp(x));
        console.log(Number(ethers.utils.formatEther(result)));
        console.log(Number(ethers.utils.formatEther(expected)));
        expect(Number(ethers.utils.formatEther(result))).to.be.equal(
          Number(ethers.utils.formatEther(expected))
        );
      });

      it("Should revert when x >= floor(log((2**255 -1) / 1e18) * 1e18)", async function () {
        const x = "135.305999368893231589";
        const fn = MockFixedPointMath.exp(fp(x));
        await expect(fn).to.be.revertedWith("ELF#009"); //INVALID_EXPONENT
      });
    });
  });
});
