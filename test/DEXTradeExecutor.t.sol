// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "v2-periphery/interfaces/IUniswapV2Router02.sol";

import "../src/DEXTradeExecutor.sol";
import "../src/interfaces/IERC20.sol";
import "../src/interfaces/IWETH.sol";

contract DEXTradeExecutorTest is Test {
    DEXTradeExecutor public tradeExecutor;
    IUniswapV2Router02 public uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    WETH public weth = WETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public badger = 0x3472A5A71965499acd81997a54BBA8D852C6E53d;

    address public account1 = 0x95abDa53Bc5E9fBBDce34603614018d32CED219e;
    address public account2 = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
    address public wbtcWhale = 0x6daB3bCbFb336b29d06B9C793AEF7eaA57888922;

    function setUp() public {
        vm.deal(address(account1), 100 ether);
        vm.deal(address(account2), 100 ether);
        vm.deal(address(wbtcWhale), 100 ether);

        vm.startPrank(account1);
        tradeExecutor = new DEXTradeExecutor(address(uniswapRouter), usdc);
        weth.deposit{value: 100 ether}();
        weth.transfer(address(tradeExecutor), 100 ether);
        vm.stopPrank();
    }

    function testSingleTrade() public {

        // 100 WBTC swap to create a profit opportunity
        vm.startPrank(wbtcWhale);
        approveAndSwap(wbtc, address(weth), 10000000000);
        vm.stopPrank();

        DEXTradeExecutor.TradeInstruction[] memory trades = new DEXTradeExecutor.TradeInstruction[](1);
        trades[0] = DEXTradeExecutor.TradeInstruction(
            address(weth),
            wbtc,
            .1 ether,
            0,
            10
        );

        vm.startPrank(account1);
        tradeExecutor.executeTrade(trades, false);
        vm.stopPrank();
    }

    function testManyTrades() public {

        // 100 WETH swap to create a profit opportunity
        vm.startPrank(account2);
        weth.deposit{value: 100 ether}();
        approveAndSwap(address(weth), badger, 100 ether);
        vm.stopPrank();


        DEXTradeExecutor.TradeInstruction[] memory trades = new DEXTradeExecutor.TradeInstruction[](4);
        trades[0] = DEXTradeExecutor.TradeInstruction(
            address(weth),
            usdc, 
            1 ether,
            0,
            10
        );

        // trade USDC for WBTC
        trades[1] = DEXTradeExecutor.TradeInstruction(
            usdc,
            wbtc,
            1500000000,
            0,
            10
        );

        trades[2] = DEXTradeExecutor.TradeInstruction(
            wbtc,
            badger,
            344216,
            0,
            10
        );

        trades[3] = DEXTradeExecutor.TradeInstruction(
            badger,
            address(weth),
            32857019798394004559,
            0,
            10
        );

        vm.startPrank(account1);
        tradeExecutor.executeTrade(trades, true);
        vm.stopPrank();
    }

     function testProfitCheck() public {

        DEXTradeExecutor.TradeInstruction[] memory trades = new DEXTradeExecutor.TradeInstruction[](1);
        trades[0] = DEXTradeExecutor.TradeInstruction(
            address(weth),
            usdc,
            .1 ether,
            0,
            10
        );

        vm.startPrank(account1);
        vm.expectRevert("Trade did not result in profit");
        tradeExecutor.executeTrade(trades, false);
        vm.stopPrank();
    }

    function testSettingProfitToken() public {
        assertEq(tradeExecutor.profitTakingToken(), usdc);
        vm.startPrank(account1);
        tradeExecutor.setProfitTakingToken(wbtc);
        vm.stopPrank();
        assertEq(tradeExecutor.profitTakingToken(), wbtc);
    }

    function testAccess() public {
        vm.startPrank(account2);
        vm.expectRevert("UNAUTHORIZED");
        tradeExecutor.setProfitTakingToken(badger);
        vm.stopPrank();
    }

    function testSendToken() public {
        uint256 accountsWethBalBefore = weth.balanceOf(address(account1));
        uint256 tradeExecutorWethBalBefore = weth.balanceOf(address(tradeExecutor));

        address[] memory token = new address[](1);
        token[0] = address(weth);

        uint256[] memory amount = new uint256[](1);
        amount[0] = tradeExecutorWethBalBefore;

        address[] memory to = new address[](1);
        to[0] = account1;

        vm.startPrank(account1);
        tradeExecutor.sendToken(token, to, amount);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(account1)), accountsWethBalBefore + tradeExecutorWethBalBefore);
        assertEq(weth.balanceOf(address(tradeExecutor)), 0);
    }

    function getPathForToken(address tokenIn, address tokenOut) private pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        return path;
    }

    function approveAndSwap(address _tokenIn, address _tokenOut, uint256 _amount) public {
        IERC20(_tokenIn).approve(address(uniswapRouter), _amount);
        uniswapRouter.swapExactTokensForTokens(
                _amount,
                0,
                getPathForToken(_tokenIn, _tokenOut),
                msg.sender,
                block.timestamp
            );
    }
}
