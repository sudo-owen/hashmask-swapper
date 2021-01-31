// SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestNCT is ERC20 {

  constructor() ERC20("Test", "TEST") public {
  }

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}