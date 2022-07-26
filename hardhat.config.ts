import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";
import "@typechain/hardhat";
import "@typechain/ethers-v5";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "tsconfig-paths/register";
import "hardhat-contract-sizer";

import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  typechain: {
    outDir: "typechain-types/",
    target: "ethers-v5",
    alwaysGenerateOverloads: true,
    externalArtifacts: ["externalArtifacts/*.json"],
  },
  solidity: {
    compilers: [
      {
        version: "0.8.15",
        settings: {
          optimizer: {
            enabled: true,
            runs: 7500,
          },
          viaIR: true,
        },
      },
    ],
  },
  mocha: { timeout: 0 },
  networks: {
    hardhat: {
      // forking: {
      //   url: "https://eth-mainnet.alchemyapi.io/v2/kwjMP-X-Vajdk1ItCfU-56Uaq1wwhamK",
      //   blockNumber: 11853372,
      // },
      accounts: {
        accountsBalance: "100000000000000000000000", // 100000 ETH
        count: 5,
      },
    },
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: false,
  },
};

export default config;
