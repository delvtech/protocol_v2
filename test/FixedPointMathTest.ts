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

function add(x: string, y: string): string {
  return (<MathjsBigNumber>math.add!(mbn(x), mbn(y))).toString();
}

function sub(x: string, y: string): string {
  return (<MathjsBigNumber>math.subtract!(mbn(x), mbn(y))).toString();
}

function pow(x: string, y: string): string {
  return (<MathjsBigNumber>math.pow!(mbn(x), mbn(y))).toString();
}

function exp(x: string): string {
  return (<MathjsBigNumber>math.exp!(mbn(x))).toString();
}

function ln(x: string): string {
  return (<MathjsBigNumber>math.log!(mbn(x), mbn(math.e))).toString();
}

chai.use(chaiAlmost(1e-5));
describe("FixedPointMath Tests", function () {
  let MockFixedPointMath: MockFixedPointMath;

  before(async () => {
    const factory = await ethers.getContractFactory("MockFixedPointMath");
    MockFixedPointMath = await factory.deploy();
  });

  context("add()", function () {
    const addTests = [
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
      ["1", "289480223093290488558927462521719769633.174961664101410098"], // Handles y = _MILD_EXPONENT_BOUND = 2^254 / 1e20
    ];

    describe("Untyped", function () {
      forEach(addTests).it(
        "handles %s+%s",
        async function (x: string, y: string) {
          const expected = fp(add(x, y));
          const result = await MockFixedPointMath.add(fp(x), fp(y));
          //console.log(Number(ethers.utils.formatEther(result)));
          //console.log(Number(ethers.utils.formatEther(expected)));
          expect(Number(ethers.utils.formatEther(result))).to.be.equal(
            Number(ethers.utils.formatEther(expected))
          );
        }
      );
    }); // End Untyped

    describe("Typed", function () {
      forEach(addTests).it(
        "handles %s+%s",
        async function (x: string, y: string) {
          const expected = fp(add(x, y));
          const result = await MockFixedPointMath.addTyped(fp(x), fp(y));
          expect(Number(ethers.utils.formatEther(result))).to.be.equal(
            Number(ethers.utils.formatEther(expected))
          );
        }
      );
    }); //End Typed
  }); // End add()

  context("sub()", function () {
    const subTests = [
      ["1", "0"],
      ["1", "1"],
      ["23", "3"],
      ["4", "0.5"],
      ["0.525", "0.5"],
      ["1e-18", "1e-18"],
      ["0.9", "0.8"],
      ["11", "0.24"],
      ["0.7373", "0.5"],
      ["69", "0.799291"],
      ["1", "0.1"],
      ["32.15", "0.99"],
      ["406", "0.25"],
      ["1729", "0.98"],
      ["2345.321", "0.0002383475"],
      ["10358673923948475759392", "0.00033928745"],
      ["45683725649", "0.001891"],
      ["340282366920938463463374607431768211455", "0.0021"], // 2^128 - 1
    ];

    describe("Untyped", function () {
      forEach(subTests).it(
        "handles %s-%s",
        async function (x: string, y: string) {
          const expected = fp(sub(x, y));
          const result = await MockFixedPointMath.sub(fp(x), fp(y));
          //console.log(Number(ethers.utils.formatEther(result)));
          //console.log(Number(ethers.utils.formatEther(expected)));
          expect(Number(ethers.utils.formatEther(result))).to.be.equal(
            Number(ethers.utils.formatEther(expected))
          );
        }
      );
    }); // End Untyped

    describe("Typed", function () {
      forEach(subTests).it(
        "handles %s-%s",
        async function (x: string, y: string) {
          const expected = fp(sub(x, y));
          const result = await MockFixedPointMath.subTyped(fp(x), fp(y));
          expect(Number(ethers.utils.formatEther(result))).to.be.equal(
            Number(ethers.utils.formatEther(expected))
          );
        }
      );
    }); //End Typed
  }); // End sub()

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
      ["1", "289480223093290488558927462521719769633.174961664101410098"], // Handles y = _MILD_EXPONENT_BOUND = 2^254 / 1e20
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
      it("Should revert when pow(10000, 2^254/1e20)=exp(yln(x)) >= floor(ln((2**255-1) / 1e18) * 1e18)", async function () {
        const x = "10000";
        const y = "289480223093290488558927462521719769633.174961664101410098";
        const fn = MockFixedPointMath.pow(fp(x), fp(y));
        await expect(fn).to.be.revertedWith("ELF#009"); //INVALID_EXPONENT in exp()
      });

      it("Should revert when pow(2**255/1e18,1) bc x overflows an int256", async function () {
        const x =
          "57896044618658097711785492504343953926634992332820282019728.792003956564819968";
        const y = "1";
        const fn = MockFixedPointMath.pow(fp(x), fp(y));
        await expect(fn).to.be.revertedWith("ELF#006"); //X_OUT_OF_BOUNDS in _ln()
      });
    }); // End Untyped

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
      it("Should revert when yln(x) >= floor(log((2**255-1) / 1e18) * 1e18)", async function () {
        const x = "10000";
        const y = "289480223093290488558927462521719769633";
        const fn = MockFixedPointMath.powTyped(fp(x), fp(y));
        await expect(fn).to.be.revertedWith("ELF#009"); //INVALID_EXPONENT in exp()
      });
      it("Should revert when pow(2**255/1e18,1) bc x overflows an int256", async function () {
        const x =
          "57896044618658097711785492504343953926634992332820282019728.792003956564819968";
        const y = "1";
        const fn = MockFixedPointMath.pow(fp(x), fp(y));
        await expect(fn).to.be.revertedWith("ELF#006"); //X_OUT_OF_BOUNDS in _ln()
      });
    }); //End Typed
  }); // End pow()

  context("exp()", function () {
    const expTests = [
      ["0"],
      ["1"],
      ["130.700829182905140221"], // _MAX_NATURAL_EXPONENT = ln((2^255 - 1) / 10^20)
      ["-41.446531673892822312"], // _MIN_NATURAL_EXPONENT = ln(10^(-18))
      ["-42.139678854452767551"],
      ["-3e18"],
      ["-2e18"],
      ["50.000000000000000001"],
      ["135.305999368893231588"],
    ];

    describe("Untyped", function () {
      forEach(expTests).it("handles e^(%s)", async function (x: string) {
        const expected = fp(exp(x));
        const result = await MockFixedPointMath.exp(fp(x));
        //console.log(Number(ethers.utils.formatEther(result)));
        //console.log(Number(ethers.utils.formatEther(expected)));
        expect(Number(ethers.utils.formatEther(result))).to.be.equal(
          Number(ethers.utils.formatEther(expected))
        );
      });

      it("Should return zero when floor(ln(0.5e18) * 1e18)", async function () {
        const expected = fp("0");
        const x = "-42.139678854452767551";
        const result = await MockFixedPointMath.exp(fp(x));
        //console.log(Number(ethers.utils.formatEther(result)));
        //console.log(Number(ethers.utils.formatEther(expected)));
        expect(Number(ethers.utils.formatEther(result))).to.be.equal(
          Number(ethers.utils.formatEther(expected))
        );
      });

      it("Should revert when x >= floor(log((2**255-1) / 1e18) * 1e18)", async function () {
        const x = "135.305999368893231589";
        const fn = MockFixedPointMath.exp(fp(x));
        await expect(fn).to.be.revertedWith("ELF#009"); //INVALID_EXPONENT in _ln()
      });
    }); // End Untyped
  }); // End exp()

  context("ln()", function () {
    const lnTests = [
      ["1"],
      ["340282366920938463463374607431768211456"], // 2**128
      ["1361129467683753853853498429727072845824"], // 2**130
      ["1427247692705959881058285969449495136382746624"], // 2**150
      ["1532495540865888858358347027150309183618739122183602176"], // 2**180
      ["1e50"],
      ["1e9"],
      ["1e5"],
      ["11723640096265400935"],
      ["2718281828459045235"],
      [
        "57896044618658097711785492504343953926634992332820282019728.792003956564819967",
      ], // 2**255-1/1e18
    ];

    describe("Untyped", function () {
      forEach(lnTests).it("handles ln(%s)", async function (x: string) {
        const expected = fp(ln(x));
        const result = await MockFixedPointMath.ln(fp(x));
        //console.log(Number(ethers.utils.formatEther(result)));
        //console.log(Number(ethers.utils.formatEther(expected)));
        expect(Number(ethers.utils.formatEther(result))).to.be.equal(
          Number(ethers.utils.formatEther(expected))
        );
      });

      // NOTE: We test that ln(2**255/1e18) overflows the int256
      // and triggers X_OUT_OF_BOUNDS in ln() thru a test in pow()
      // bc we get this error when doing it directly:
      // > AssertionError: Expected transaction to be reverted with ELF#006,
      // > but other exception was thrown: Error: value out-of-bounds
      // > (argument="x", value={"type":"BigNumber","hex":"0x8000000000000000000000000000000000000000000000000000000000000000"},
      // > code=INVALID_ARGUMENT, version=abi/5.6.3)

      it("Should revert when x == 0)", async function () {
        const x = fp("0");
        const fn = MockFixedPointMath.ln(x);
        await expect(fn).to.be.revertedWith("ELF#006"); // X_OUT_OF_BOUNDS in ln()
      });

      it("Should revert when x < 0)", async function () {
        const x = fp("-1");
        const fn = MockFixedPointMath.ln(x);
        await expect(fn).to.be.revertedWith("ELF#006"); // X_OUT_OF_BOUNDS in ln()
      });
    }); // End Untyped
  }); // End ln()
}); // End FixedPointMath Tests
