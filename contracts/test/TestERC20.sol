// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
  constructor() ERC20("TEST ERC20 TOKEN", "TESTERC20") {}

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}
