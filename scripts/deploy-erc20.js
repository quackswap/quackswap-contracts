const { ethers } = require('hardhat');


async function main() {

    const [deployer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);

    // Deploy StakingRewards
    const DummyERC20 = await ethers.getContractFactory("DummyERC20");
    const dummyErc20 = await DummyERC20.deploy(
        "Dummy ERC20",
        "PGL",
        deployer.address,
        '100000000000000000000000000', // arbitrary amount
    );
    await dummyErc20.deployed();

    console.log("StakingRewards address: ", dummyErc20.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
