// SPDX-License-Identifier: MIT

pragma solidity >=0.4.25 <0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IAuction.sol";

contract Auction is IAuction, AccessControl {
    using SafeMath for uint256;

    bytes32 public constant CALLER_ROLE = keccak256("CALLER_ROLE");

    struct AuctionReserves {
        uint256 eth;
        uint256 token;
    }

    struct UserBet {
        uint256 eth;
        address ref;
    }

    mapping(uint256 => AuctionReserves) public reservesOf;
    mapping(address => uint256[]) public auctionsOf;
    mapping(uint256 => mapping(address => bool)) public existAuctionsOf;
    mapping(uint256 => mapping(address => UserBet)) public auctionEthBalanceOf;

    uint256 public start;
    uint256 public currentAuctionId;
    uint256 public stepTimestamp;
    address public mainToken;
    address public staking;
    address payable public uniswap;
    address payable public recipient;
    bool public init_;

    constructor() public {
        init_ = false;
    }

    function init(
        uint256 _stepTimestamp,
        address _mainToken,
        address _staking,
        address payable _uniswap,
        address payable _recipient,
        address _nativeSwap,
        address _foreignSwap
    ) external {
        require(!init_, "init is active");
        _setupRole(CALLER_ROLE, _nativeSwap);
        _setupRole(CALLER_ROLE, _foreignSwap);
        start = now;
        stepTimestamp = _stepTimestamp;
        mainToken = _mainToken;
        staking = _staking;
        uniswap = _uniswap;
        recipient = _recipient;
        init_ = true;
    }

    function getUserEthBalanceInAuction(uint256 auctionId, address account)
        public
        view
        returns (uint256)
    {
        return auctionEthBalanceOf[auctionId][account].eth;
    }

    function getUserRefInAuction(uint256 auctionId, address account)
        public
        view
        returns (address)
    {
        return auctionEthBalanceOf[auctionId][account].ref;
    }

    function bet(uint256 deadline, address ref) external payable {
        require(_msgSender() != ref, "msg.sender == ref");

        (
            uint256 toRecipient,
            uint256 toUniswap
        ) = _calculateRecipientAndUniswapAmountsToSend();

        _swapEth(toUniswap, deadline);

        uint256 stepsFromStart = calculateStepsFromStart();

        currentAuctionId = stepsFromStart;

        auctionEthBalanceOf[stepsFromStart][_msgSender()].ref = ref;

        auctionEthBalanceOf[stepsFromStart][_msgSender()]
            .eth = auctionEthBalanceOf[stepsFromStart][_msgSender()].eth.add(
            msg.value
        );

        if (!existAuctionsOf[stepsFromStart][_msgSender()]) {
            auctionsOf[_msgSender()].push(stepsFromStart);
            existAuctionsOf[stepsFromStart][_msgSender()] = true;
        }

        reservesOf[stepsFromStart].eth = reservesOf[stepsFromStart].eth.add(
            msg.value
        );

        recipient.transfer(toRecipient);
    }

    function withdraw(uint256 auctionId) external {
        uint256 stepsFromStart = calculateStepsFromStart();

        require(stepsFromStart > auctionId, "auction is active");


            uint256 auctionETHUserBalance
         = auctionEthBalanceOf[auctionId][_msgSender()].eth;

        require(auctionETHUserBalance > 0, "zero balance in auction");

        uint256 payout = _calculatePayout(auctionId, auctionETHUserBalance);

        auctionEthBalanceOf[auctionId][_msgSender()].eth = 0;

        if (
            address(auctionEthBalanceOf[auctionId][_msgSender()].ref) ==
            address(0)
        ) {
            IERC20(mainToken).transfer(_msgSender(), payout);
        } else {
            IERC20(mainToken).transfer(_msgSender(), payout);

            (
                uint256 toRefMintAmount,
                uint256 toUserMintAmount
            ) = _calculateRefAndUserAmountsToMint(payout);

            IToken(mainToken).mint(_msgSender(), toUserMintAmount);

            IToken(mainToken).mint(
                auctionEthBalanceOf[auctionId][_msgSender()].ref,
                toRefMintAmount
            );
        }
    }

    function callIncomeTokensTrigger(uint256 incomeAmountToken)
        external
        override
    {
        require(
            hasRole(CALLER_ROLE, _msgSender()),
            "Caller is not a caller role"
        );

        uint256 stepsFromStart = calculateStepsFromStart();

        reservesOf[stepsFromStart].token = reservesOf[stepsFromStart].token.add(
            incomeAmountToken
        );
    }

    function calculateStepsFromStart() public view returns (uint256) {
        return now.sub(start).div(stepTimestamp);
    }

    function _calculatePayout(uint256 auctionId, uint256 amountEth)
        internal
        view
        returns (uint256)
    {
        return
            amountEth.mul(reservesOf[auctionId].token).div(
                reservesOf[auctionId].eth
            );
    }

    function _calculateRecipientAndUniswapAmountsToSend()
        private
        returns (uint256, uint256)
    {
        uint256 toRecipient = msg.value.mul(20).div(100);
        uint256 toUniswap = msg.value.sub(toRecipient);

        return (toRecipient, toUniswap);
    }

    function _calculateRefAndUserAmountsToMint(uint256 amount)
        private
        pure
        returns (uint256, uint256)
    {
        uint256 toRefMintAmount = amount.mul(10).div(100);
        uint256 toUserMintAmount = amount.mul(20).div(100);

        return (toRefMintAmount, toUserMintAmount);
    }

    function _swapEth(uint256 amount, uint256 deadline) private {
        address[] memory path = new address[](2);

        path[0] = IUniswapV2Router02(uniswap).WETH();
        path[1] = mainToken;

        uint256[] memory amountsOut = IUniswapV2Router02(uniswap).getAmountsOut(
            amount,
            path
        );

        IUniswapV2Router02(uniswap).swapExactETHForTokens{value: amount}(
            amountsOut[1],
            path,
            staking,
            deadline
        );
    }
}
