// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "v2-periphery/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IERC20.sol";
import "solmate/auth/Owned.sol";


error NoProfit();
error SlippageExceeded();
error TokenMismatch();
error ArrLengthMismatch();

contract DEXTradeExecutor is Owned {
    struct TradeInstruction {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 slippageTolerance;
    }

    IUniswapV2Router02 public uniswapRouter;
    address public profitTakingToken;

    constructor(address _uniswapRouter, address _profitTakingToken) Owned(msg.sender) {
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        profitTakingToken = _profitTakingToken;
    }

    function executeTrade(TradeInstruction[] memory _trades, bool feedOutputIn) public onlyOwner {
        uint256 valueBeforeTrade;
        uint256 valueAfterTrade;
        uint256 actualTokensOut;

        for (uint256 i = 0; i < _trades.length; i++) {
            if(feedOutputIn && i != 0) {
                // Output of previous trade must be input of next trade
                if (_trades[i - 1].tokenOut != _trades[i].tokenIn)
                    revert TokenMismatch();

                _trades[i].amountIn = actualTokensOut;
            }
            valueBeforeTrade += getAmountInProfitToken(_trades[i].tokenIn, _trades[i].amountIn);
            actualTokensOut = swapOnUinswap(_trades[i]);
            valueAfterTrade += getAmountInProfitToken(_trades[i].tokenOut, actualTokensOut);
        }
        if(valueAfterTrade <= valueBeforeTrade)
            revert NoProfit();
    }

    function swapOnUinswap(TradeInstruction memory trade) private returns (uint256) {
        IERC20(trade.tokenIn).approve(address(uniswapRouter), trade.amountIn);

        address[] memory path = getPathForToken(trade.tokenIn, trade.tokenOut);
        uint256[] memory amounts = uniswapRouter.getAmountsOut(trade.amountIn, path);
        
        uint256 amountOut = amounts[amounts.length - 1];
        uint256 slippageAmount = (amountOut * trade.slippageTolerance) / 100;
        if (amountOut - slippageAmount < trade.amountOutMin)
            revert SlippageExceeded();

        uint256[] memory results = uniswapRouter.swapExactTokensForTokens(
            trade.amountIn,
            trade.amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        return results[results.length - 1];
    }

    //Helper to quickly return a sized array
    function getPathForToken(address tokenIn, address tokenOut) private pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        return path;
    }

    function sendToken(address[] calldata _token, address[] calldata _to, uint256[] calldata _amount) public onlyOwner {
        if (_token.length != _to.length || _to.length != _amount.length)
            revert ArrLengthMismatch();
            
        for (uint i = 0; i < _token.length; i++) {
            IERC20(_token[i]).transfer(_to[i], _amount[i]);   
        }
    }

    // Returns the amount of profit taking token that would be received for the given amount of tokenIn
    function getAmountInProfitToken(address _token, uint256 _amount) private view returns (uint256) {
        if (_token == profitTakingToken) {
            return _amount;
        }
        address[] memory path = getPathForToken(_token, profitTakingToken);
        uint256[] memory amounts = uniswapRouter.getAmountsOut(_amount, path);
        return amounts[amounts.length - 1];
    }

    function setProfitTakingToken(address _token) public onlyOwner {
        profitTakingToken = _token;
    }
}
