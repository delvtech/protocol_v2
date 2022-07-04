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

export function pow(x: string, y: string): string {
  return (<MathjsBigNumber>math.pow!(mbn(x), mbn(y))).toString();
}

chai.use(chaiAlmost(1e-5));
describe("FixedPointMath Tests", function () {
  let MockFixedPointMath: MockFixedPointMath;

  before(async () => {
    const factory = await ethers.getContractFactory("MockFixedPointMath");
    MockFixedPointMath = await factory.deploy();
  });

  const testSets = [
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

  describe("pow()", function () {
    forEach(testSets).it(
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

  describe("powTyped()", function () {
    forEach(testSets).it(
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
