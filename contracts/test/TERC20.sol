// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract TERC20 is ERC20 {
    using SafeMath for uint256;

    constructor(
        string memory name,
        string memory symbol,
        uint256 amountToMint
    ) public ERC20(name, symbol) {
        _mint(msg.sender, amountToMint.mul(1e18));
    }
}
