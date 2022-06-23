pragma solidity >=0.5.0;

import "../../quackswap-core/interfaces/IQuackSwapERC20.sol";

interface IBridgeToken is IQuackSwapERC20 {
    function swap(address token, uint256 amount) external;
    function swapSupply(address token) external view returns (uint256);
}
