pragma solidity =0.6.6;

import '../quackswap-core/interfaces/IQuackSwapFactory.sol';
import '../quackswap-lib/libraries/TransferHelper.sol';

import './interfaces/IQuackSwapRouter.sol';
import './libraries/QuackSwapLibrary.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWBTT.sol';

contract QuackSwapRouter is IQuackSwapRouter {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WBTT;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'QuackSwapRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WBTT) public {
        factory = _factory;
        WBTT = _WBTT;
    }

    receive() external payable {
        assert(msg.sender == WBTT); // only accept BTT via fallback from the WBTT contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IQuackSwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IQuackSwapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = QuackSwapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = QuackSwapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'QuackSwapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = QuackSwapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'QuackSwapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = QuackSwapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IQuackSwapPair(pair).mint(to);
    }
    function addLiquidityBTT(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountBTTMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountBTT, uint liquidity) {
        (amountToken, amountBTT) = _addLiquidity(
            token,
            WBTT,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountBTTMin
        );
        address pair = QuackSwapLibrary.pairFor(factory, token, WBTT);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWBTT(WBTT).deposit{value: amountBTT}();
        assert(IWBTT(WBTT).transfer(pair, amountBTT));
        liquidity = IQuackSwapPair(pair).mint(to);
        // refund dust BTT, if any
        if (msg.value > amountBTT) TransferHelper.safeTransferBTT(msg.sender, msg.value - amountBTT);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = QuackSwapLibrary.pairFor(factory, tokenA, tokenB);
        IQuackSwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IQuackSwapPair(pair).burn(to);
        (address token0,) = QuackSwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'QuackSwapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'QuackSwapRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityBTT(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountBTTMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountBTT) {
        (amountToken, amountBTT) = removeLiquidity(
            token,
            WBTT,
            liquidity,
            amountTokenMin,
            amountBTTMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWBTT(WBTT).withdraw(amountBTT);
        TransferHelper.safeTransferBTT(to, amountBTT);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = QuackSwapLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IQuackSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityBTTWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountBTTMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountBTT) {
        address pair = QuackSwapLibrary.pairFor(factory, token, WBTT);
        uint value = approveMax ? uint(-1) : liquidity;
        IQuackSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountBTT) = removeLiquidityBTT(token, liquidity, amountTokenMin, amountBTTMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityBTTSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountBTTMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountBTT) {
        (, amountBTT) = removeLiquidity(
            token,
            WBTT,
            liquidity,
            amountTokenMin,
            amountBTTMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWBTT(WBTT).withdraw(amountBTT);
        TransferHelper.safeTransferBTT(to, amountBTT);
    }
    function removeLiquidityBTTWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountBTTMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountBTT) {
        address pair = QuackSwapLibrary.pairFor(factory, token, WBTT);
        uint value = approveMax ? uint(-1) : liquidity;
        IQuackSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountBTT = removeLiquidityBTTSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountBTTMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = QuackSwapLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? QuackSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IQuackSwapPair(QuackSwapLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = QuackSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'QuackSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, QuackSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = QuackSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'QuackSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, QuackSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactBTTForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WBTT, 'QuackSwapRouter: INVALID_PATH');
        amounts = QuackSwapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'QuackSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWBTT(WBTT).deposit{value: amounts[0]}();
        assert(IWBTT(WBTT).transfer(QuackSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactBTT(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WBTT, 'QuackSwapRouter: INVALID_PATH');
        amounts = QuackSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'QuackSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, QuackSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWBTT(WBTT).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferBTT(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForBTT(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WBTT, 'QuackSwapRouter: INVALID_PATH');
        amounts = QuackSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'QuackSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, QuackSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWBTT(WBTT).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferBTT(to, amounts[amounts.length - 1]);
    }
    function swapBTTForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WBTT, 'QuackSwapRouter: INVALID_PATH');
        amounts = QuackSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'QuackSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        IWBTT(WBTT).deposit{value: amounts[0]}();
        assert(IWBTT(WBTT).transfer(QuackSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust BTT, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferBTT(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = QuackSwapLibrary.sortTokens(input, output);
            IQuackSwapPair pair = IQuackSwapPair(QuackSwapLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = QuackSwapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? QuackSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, QuackSwapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'QuackSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactBTTForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WBTT, 'QuackSwapRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWBTT(WBTT).deposit{value: amountIn}();
        assert(IWBTT(WBTT).transfer(QuackSwapLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'QuackSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForBTTSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WBTT, 'QuackSwapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, QuackSwapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WBTT).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'QuackSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWBTT(WBTT).withdraw(amountOut);
        TransferHelper.safeTransferBTT(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return QuackSwapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return QuackSwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return QuackSwapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return QuackSwapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return QuackSwapLibrary.getAmountsIn(factory, amountOut, path);
    }
}
