# Element Protocol 👯‍♀️

[![Build Status](https://github.com/element-fi/protocol_v2/workflows/Tests/badge.svg)](https://github.com/element-fi/protocol_v2/actions)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/element-fi/elf-contracts/blob/master/LICENSE)

The Element Protocol is a DeFi primitive which runs on the Ethereum blockchain. The Protocol, at its core, allows a tokenized yield bearing position (ETH, BTC, USDC, etc) to be split into principal and yield tokens. The principal tokens are redeemable for the deposited principal and the yield tokens are redeemable for the yield earned over the term period. This splitting mechanism allows users to sell their principal as a fixed-rate income position, further leveraging or increasing exposure to interest without any liquidation risk.

## Prerequisites

**Install nvm & node**
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
source ~/.bashrc
nvm install 14.18.0
```
**Install Foundry**
```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
```

## Clone the repo

```
git clone --recurse-submodules git@github.com:element-fi/protocol_v2.git
```

## Hardhat Config
```
cd protocol_v2
npm install
```

### Build

```
npm run build
```

### Test

```
npm run test
```
## Foundry Config

Some tests are run using Foundry. The following instructions will walk you through the setup

### Configure repository

If you forgot to include the `--recurse-submodules` flag when cloning, then run the following command:

```
git submodule update --init --recursive
```

### Run Foundry tests

```
forge test
```

### Add modules for Foundry

Foundry install directly from github.  In order to install a new module, you simply need to run:

```
forge install GH_NAMESPACE/GH_REPO
# i.e.
forge install Openzeppelin/openzeppelin-contracts
```

If this works, you'll see that the .gitmodules file has been updated:
```
[submodule "lib/openzeppelin-contracts"]
	path = lib/openzeppelin-contracts
	url = https://github.com/Openzeppelin/openzeppelin-contracts
```

In order to import from the module, you'll need to update foundry.toml:
```
remappings = ['forge-std=lib/forge-std/src', '@openzeppelin/=lib/openzeppelin-contracts']
```