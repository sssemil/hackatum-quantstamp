// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

import "./IBank.sol";

contract Bank is IBank {
  function deposit(address token, uint256 amount)
    external
    payable
    override
    returns (bool)
  {
    // TODO
    return false;
  }

  function withdraw(address token, uint256 amount)
    external
    override
    returns (uint256)
  {
    // TODO
    return 0;
  }

  function borrow(address token, uint256 amount)
    external
    override
    returns (uint256)
  {
    // TODO
    return 0;
  }

  function repay(address token, uint256 amount)
    external
    payable
    override
    returns (uint256)
  {
    // TODO
    return 0;
  }

  function liquidate(address token, address account)
    external
    payable
    override
    returns (bool)
  {
    // TODO
    return false;
  }

  function getCollateralRatio(address token, address account)
    external
    view
    override
    returns (uint256)
  {
    // TODO
    return 0;
  }

  function getBalance(address token) external view override returns (uint256) {
    // TODO
    return 0;
  }
}
