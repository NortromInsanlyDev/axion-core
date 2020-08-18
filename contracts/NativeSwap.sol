// SPDX-License-Identifier: MIT

pragma solidity >=0.4.25 <0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IAuction.sol";

contract NativeSwap {
    using SafeMath for uint256;

    uint256 private start;
    uint256 private stepTimestamp;
    address private swapToken;
    address private mainToken;
    address private dailyAuction;

    bool public init0;
    bool public init1;

    mapping(address => uint256) private swapTokenBalanceOf;

    constructor() public {
        init0 = false;
        init1 = false;
    }

    function init_0(
        uint256 _stepTimestamp,
        address _swapToken,
        address _mainToken
    ) external {
        require(!init0, "init0 is active");
        stepTimestamp = _stepTimestamp;
        swapToken = _swapToken;
        mainToken = _mainToken;
        init0 = true;
    }

    function init_1(address _dailyAuction) external {
        require(!init1, "init0 is active");
        dailyAuction = _dailyAuction;
        start = now;
        init1 = true;
    }

    function getStart() external view returns (uint256) {
        return start;
    }

    function getStepTimestamp() external view returns (uint256) {
        return stepTimestamp;
    }

    function getSwapToken() external view returns (address) {
        return swapToken;
    }

    function getMainToken() external view returns (address) {
        return mainToken;
    }

    function getDailyAuction() external view returns (address) {
        return dailyAuction;
    }

    function getSwapTokenBalanceOf(address account)
        external
        view
        returns (uint256)
    {
        return swapTokenBalanceOf[account];
    }

    function deposit(uint256 _amount) external {
        IERC20(swapToken).transferFrom(msg.sender, address(this), _amount);
        swapTokenBalanceOf[msg.sender] = swapTokenBalanceOf[msg.sender].add(
            _amount
        );
    }

    function withdraw(uint256 _amount) external {
        require(_amount >= swapTokenBalanceOf[msg.sender], "balance < amount");
        swapTokenBalanceOf[msg.sender] = swapTokenBalanceOf[msg.sender].sub(
            _amount
        );
        IERC20(swapToken).transfer(msg.sender, _amount);
    }

    function swapNativeToken() external {
        uint256 amount = swapTokenBalanceOf[msg.sender];
        uint256 deltaPenalty = _calculateDeltaPenalty(amount);
        uint256 amountOut = amount.sub(deltaPenalty);
        require(amount > 0, "swapNativeToken: amount == 0");
        swapTokenBalanceOf[msg.sender] = 0;
        IToken(mainToken).mint(dailyAuction, deltaPenalty);
        IAuction(dailyAuction).callIncomeTokensTrigger(deltaPenalty);
        IToken(mainToken).mint(msg.sender, amountOut);
    }

    function _calculateDeltaPenalty(uint256 amount)
        internal
        view
        returns (uint256)
    {
        uint256 stepsFromStart = (now.sub(start)).div(stepTimestamp);
        return amount.mul(stepsFromStart).div(350);
    }
}