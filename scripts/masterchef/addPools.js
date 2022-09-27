    const { ethers, network } = require('hardhat');
    const {from} = require('rxjs');
    const {concatMap} = require('rxjs/operators');
    const {masterChefAddress, pools} = require('./poolConfig.json');
    const BATCH_SIZE = 50;
    
    const addPools = masterChef => async (poolsConfig) => {
      const params = [
        pools.map(entry => entry.alloc),
        pools.map(entry => entry.address),
        pools.map(entry => ethers.constants.AddressZero)
      ]
  
      await masterChef.addPools(...params)
    }
    
    const batchArray = (array, batchSize) => {
        const batches = []
    
        while(array.length) {
            batches.push(array.splice(0, batchSize));
        }
    
        return batches
    }
    
    async function main() {
        const [deployer, user1] = await ethers.getSigners();
    
        const MasterChef = await ethers.getContractFactory("MasterChef");
        const masterChef = await MasterChef.attach(masterChefAddress);
        console.log("MasterChef:", masterChef.address);
    
        const batches = batchArray([...pools], BATCH_SIZE)
        console.log("BATCH_SIZE:", BATCH_SIZE)
        console.log("Number of batches:", batches.length)
        
        await from(batches).pipe(
            concatMap(addPools(masterChef))
          ).toPromise()
    }
    
    main()
        .then(() => process.exit(0))
        .catch(error => {
            console.error(error);
            process.exit(1);
        });
    