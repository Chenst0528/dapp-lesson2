//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SwapPool is ERC20 {
  address public token0;
  address public token1;

  uint public reserve0;
  uint public reserve1;

  uint public fee; // 手续费，千分之三就是30
  //定义最小流动性
  uint public constant INITIAL_SUPPLY = 10**3;

  constructor(address _token0, address _token1) ERC20("LiquidityProvider", "LP") {
    token0 = _token0;
    token1 = _token1;
  }

  /**
   * 增加流动性
   */
  function addliq(uint amount0, uint amount1) public {
      //首先，用户将代币转移至池中
    assert(IERC20(token0).transferFrom(msg.sender, address(this), amount0));
    assert(IERC20(token1).transferFrom(msg.sender, address(this), amount1));
    //获取增加量
    uint reserve0After = reserve0 + amount0;
    uint reserve1After = reserve1 + amount1;
 // 如果这是第一个提供流动性的用户，铸造初始金额的 LP 代币
    if (reserve0 == 0 && reserve1 == 0) {
      _mint(msg.sender, INITIAL_SUPPLY);
      //否则，按比例计算份额并铸造等比例的 LP 代币
    } else {
      uint currentSupply = totalSupply();
      uint newSupplyGivenReserve0Ratio = reserve0After * currentSupply / reserve0;
      uint newSupplyGivenReserve1Ratio = reserve1After * currentSupply / reserve1;
      uint newSupply = Math.min(newSupplyGivenReserve0Ratio, newSupplyGivenReserve1Ratio);
      _mint(msg.sender, newSupply - currentSupply);
    }
    //更新储备量
    reserve0 = reserve0After;
    reserve1 = reserve1After;
  }

  /**
   * 减少流动性
   */
  function decreaseliq(uint liquidity) public {
      //首先，将代表流动性份额的 LP 代币收回
    assert(transfer(address(this), liquidity));
     //计算这部分 LP 代币在池子中代表的 token0 和 token1 的数量
    uint currentSupply = totalSupply();
    uint amount0 = liquidity * reserve0 / currentSupply;
    uint amount1 = liquidity * reserve1 / currentSupply;
    //销毁该用户的LP代币
    _burn(address(this), liquidity);
    //将 token0 和 token1 归还给该用户
    assert(IERC20(token0).transfer(msg.sender, amount0));
    assert(IERC20(token1).transfer(msg.sender, amount1));
    reserve0 = reserve0 - amount0;
    reserve1 = reserve1 - amount1;
  }

  /**
   * 使用 x * y = k 公式计算输出量
   * 1. 计算新储备量
   * 2. 新输出量
   */
  function getAmountOut (uint amountIn, address fromToken) public view returns (uint amountOut, uint _reserve0, uint _reserve1) {
    uint newReserve0;
    uint newReserve1;
    uint k = reserve0 * reserve1;

    // 式中 x 为 reserve0 （池中 token0 的数量）
    // 式中 y 为 reserve1
    // k = reserve0 * reserve1，在定价时 k 必须保持不变。
    // 如果减少了池中的 reserve0，就必须增加池中的 reserve1。

    if (fromToken == token0) {
      newReserve0 = amountIn + reserve0;
      newReserve1 = k / newReserve0;
      amountOut = reserve1 - newReserve1;
    } else {
      newReserve1 = amountIn + reserve1;
      newReserve0 = k / newReserve1;
      amountOut = reserve0 - newReserve0;
    }

    _reserve0 = newReserve0;
    _reserve1 = newReserve1;
  }

  /**
   * 交易
   */
  function swap(uint amountIn, uint minAmountOut, address fromToken, address toToken, address to) public {
    require(amountIn > 0 && minAmountOut > 0, 'Amount error');
    require(fromToken == token0 || fromToken == token1, 'From invalid');
    require(toToken == token0 || toToken == token1, 'To invalid');
    require(fromToken != toToken, 'not match');
    //用上一节的函数计算应该得到的代币数量，以及池子中两种代币的更新后的数量
    (uint amountOut, uint newReserve0, uint newReserve1) = getAmountOut(amountIn, fromToken);
    //实际交易价格与目标交易价格之差称为滑点，不合理的交易将不会被执行
    require(amountOut >= minAmountOut, 'Slipped');
    //对两个代币进行分别转账，以完成交易
    assert(IERC20(fromToken).transferFrom(msg.sender, address(this), amountIn));
    assert(IERC20(toToken).transfer(to, amountOut));

    reserve0 = newReserve0;
    reserve1 = newReserve1;
  }
}