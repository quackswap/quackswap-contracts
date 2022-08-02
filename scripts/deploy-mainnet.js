const { ethers } = require("hardhat");
const fs = require("fs");
// const { FOUNDATION_MULTISIG } = require("../constants/shared.js");
const {
    QUACK_SYMBOL,
    QUACK_NAME,
    TOTAL_SUPPLY,
    WRAPPED_NATIVE_TOKEN,
    INITIAL_FARMS,
    AIRDROP_AMOUNT,
    TREASURY_ADDRESS,
    WETH_PNG_FARM_ALLOCATION,
} = require(`../constants/${network.name}.js`);

var contracts = [];

function delay(timeout) {
    return new Promise((resolve) => {
        setTimeout(resolve, timeout);
    });
}

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("\nDeployer:", deployer.address);

    const initBalance = await deployer.getBalance();
    console.log("Balance:", ethers.utils.formatEther(initBalance) + "\n");

    if (WRAPPED_NATIVE_TOKEN === undefined || WRAPPED_NATIVE_TOKEN == "") {
        console.log("⚠️  No wrapped gas token is defined.");
    } else {
        console.log("✅ An existing wrapped gas token is defined.");
    }
    if (INITIAL_FARMS.length === 0 || INITIAL_FARMS === undefined) {
        console.log("⚠️  No initial farm is defined.");
    }

    // dirty hack to circumvent duplicate nonce submission error
    var txCount = await ethers.provider.getTransactionCount(deployer.address);
    async function confirmTransactionCount() {
        let newTxCount;
        while (true) {
            try {
                newTxCount = await ethers.provider.getTransactionCount(
                    deployer.address
                );
                if (newTxCount != txCount + 1) {
                    continue;
                }
                txCount++;
            } catch (err) {
                console.log(err);
                process.exit(0);
            }
            break;
        }
    }

    async function deploy(factory, args) {
        var ContractFactory = await ethers.getContractFactory(factory);
        var contract = await ContractFactory.deploy(...args);
        await contract.deployed();
        contracts.push({ address: contract.address, args: args });
        await confirmTransactionCount();
        console.log(contract.address, ":", factory);
        return contract;
    }

    console.log("\n============\n DEPLOYMENT \n============");

    // Deploy BTT if not defined
    if (WRAPPED_NATIVE_TOKEN === undefined) {
        var nativeToken = (await deploy("WBTT", [])).address;
    } else {
        var nativeToken = WRAPPED_NATIVE_TOKEN;
        console.log(nativeToken, ": WBTT");
    }

    /**************
     * GOVERNANCE *
     **************/

    // Deploy PNG
    const quack = await deploy("QUACK", [
        ethers.utils.parseUnits(TOTAL_SUPPLY.toString(), 18),
        ethers.utils.parseUnits(AIRDROP_AMOUNT.toString(), 18),
        QUACK_SYMBOL,
        QUACK_NAME,
    ]);

    const factory = await deploy("QuackSwapFactory", [deployer.address]);
    const router = await deploy("QuackSwapRouter", [
        factory.address,
        nativeToken,
    ]);
    const chef = await deploy("MasterChef", [quack.address, deployer.address]);

    console.log("\n===============\n CONFIGURATION \n===============");

    await quack.setMinter(chef.address);
    await confirmTransactionCount();
    console.log("Transferred QUACK minter role to to MasterChef.");


    // change swap fee recipient to fee collector
    await factory.setFeeTo(TREASURY_ADDRESS);
    await confirmTransactionCount();
    console.log("Set FeeCollector as the swap fee recipient.");

    /********************
     * MASTERCHEF FARMS *
     ********************/

    await factory.createPair(quack.address, nativeToken);
    await confirmTransactionCount();
    var quackPair = await factory.getPair(quack.address, nativeToken);
    await chef.addPool(
        WETH_PNG_FARM_ALLOCATION,
        quackPair,
        ethers.constants.AddressZero
    );
    await confirmTransactionCount();
    console.log("Added MasterChef pool 1 for BTT-QUACK.");

    // create native token paired farms for tokens in INITIAL_FARMS
    for (let i = 0; i < INITIAL_FARMS.length; i++) {
        let tokenA = INITIAL_FARMS[i]["tokenA"];
        let tokenB = INITIAL_FARMS[i]["tokenB"];
        let weight = INITIAL_FARMS[i]["weight"];
        await factory.createPair(tokenA, tokenB);
        await confirmTransactionCount();
        let pair = await factory.getPair(tokenA, tokenB);
        await chef.addPool(weight, pair, ethers.constants.AddressZero);
        await confirmTransactionCount();
    }
    const pools = await chef.poolInfos();
    if (pools.length > 2)
        console.log(
            "Added",
            (pools.length - 2).toString(),
            "more farms to MasterChef."
        );

    const endBalance = await deployer.getBalance();
    console.log(
        "\nDeploy cost:",
        ethers.utils.formatEther(initBalance.sub(endBalance)) + "\n"
    );
    console.log(
        "Recorded contract addresses to `addresses/" + network.name + ".js`."
    );
    console.log("Refer to `addresses/README.md` for Etherscan verification.\n");

    try {
        fs.writeFileSync(
            "addresses/" + network.name + ".js",
            "exports.ADDRESSES=" + JSON.stringify(contracts)
        );
        //file written successfully
    } catch (err) {
        console.error(err);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
