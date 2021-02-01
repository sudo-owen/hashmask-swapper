// SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FakeToken is ERC20 {

  constructor() ERC20("Fake", "F") public {
  }

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}