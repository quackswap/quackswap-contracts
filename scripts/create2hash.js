const { bytecode } = require('./QuackSwapPair.json')
const { keccak256 } = require('@ethersproject/solidity')

const COMPUTED_INIT_CODE_HASH = keccak256(['bytes'], [`${bytecode}`])
console.log("🚀 ~ file: create2hash.js ~ line 5 ~ COMPUTED_INIT_CODE_HASH", COMPUTED_INIT_CODE_HASH)
