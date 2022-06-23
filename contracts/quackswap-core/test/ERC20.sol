pragma solidity =0.5.16;

import '../QuackSwapERC20.sol';

contract ERC20 is QuackSwapERC20 {
    constructor(uint _totalSupply) public {
        _mint(msg.sender, _totalSupply);
    }
}
