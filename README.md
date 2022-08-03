# QuackSwap Smart Contracts
This repo contains all of the smart contracts used to run [QuackSwap](app.quackswap.exchange).

## Deployed Contracts
Factory address: ``

Router address: ``

## Running
These contracts are compiled and deployed using [Hardhat](https://hardhat.org/).

To prepare the dev environment, run `yarn install`. To compile the contracts, run `yarn compile`. Yarn is available to install [here](https://classic.yarnpkg.com/en/docs/install/#debian-stable) if you need it.

## Attribution
These contracts were adapted from these Pangolin repos: [pangolindex-exchange-contracts](https://github.com/pangolindex/exchange-contracts).

# Deployment

To deploy to any chain you want, you need to complete the following steps:
- [ ] Copy `.env.example` to `.env` and add your private key there
- [ ] Create a new configuration under `constants/NETWORK_NAME.js`
- [ ] Run the following command
```bash
yarn deploy [--network NETWORK_NAME]
```
The deployment script will deploy all the contracts and set them up according to the configuration file.

## Configuration

The deployment scripts gets chain specific configuration from the respective file in `constants/`. You can copy an existing configuration such as `constants/fantom_mainnet.js` when creating a configuration file for another chain. The deployer must be familiar with the purpose of each constant.

# Faucets

## Bittorent

Faucet: https://testfaucet.bt.io/#/
Testnet: https://test.bt.io/
## Aurora
Currently on Aurora you need to get funds into Goerli and then bridge across. You can do this by following these steps:
- Get some ETH from Chainlink Faucet https://faucets.chain.link/goerli
- Send ETH to Aurora via Rainbow Bridge https://testnet.rainbowbridge.app/

## BSC
Faucet: https://testnet.binance.org/faucet-smart
## Cronos
Faucet: https://cronos.crypto.org/faucet
Testnet Explorer: https://cronos.crypto.org/explorer/testnet3/

## Harmony
To get Harmony tokens on the testnet please go here https://faucet.pops.one/. **Please note** the Metamask address is different to your Harmony address, so you'll need to go to the Explorer to convert https://explorer.pops.one/

## Polygon (MATIC)
Faucet: https://faucet.polygon.technology/
