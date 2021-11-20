//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";
import "./libraries/Math.sol";

import "hardhat/console.sol";

contract Bank is IBank {
    using DSMath for uint256;

    address private constant etherTokenAddress =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address private priceOracle;
    address private hakTokenAddress;

    // wallet address -> token address -> Account
    mapping(address => mapping(address => Account)) private accounts;

    constructor(address _priceOracle, address _hakToken) {
        priceOracle = _priceOracle;
        hakTokenAddress = _hakToken;
    }

    function _calcInterest(uint256 lastInterestBlock, uint256 deposit)
        internal
        view
        returns (uint256)
    {
        uint256 blocksDiff = block.number.sub(lastInterestBlock);
        uint256 interest = deposit.mul(blocksDiff).mul(3).rdiv(10000);
        return interest;
    }

    function _recalcInterest(address token) internal {
        accounts[msg.sender][token].interest = accounts[msg.sender][token]
            .interest
            .add(
                _calcInterest(
                    accounts[msg.sender][token].lastInterestBlock,
                    accounts[msg.sender][token].deposit
                )
            );
        accounts[msg.sender][token].lastInterestBlock = block.number;
    }

    function deposit(address token, uint256 amount)
        external
        payable
        override
        returns (bool)
    {
        require(amount > 0, "cannot deposit zero or less");
        if (token == etherTokenAddress) {
            // eth case
            require(msg.value == amount);
        } else if (token == hakTokenAddress) {
            // hak case
            IERC20 hakTokenInstance = IERC20(token);
            // check if there's sufficient balance
            require(
                hakTokenInstance.balanceOf(msg.sender) >= amount,
                "insufficient balance"
            );
            // check if there's sufficient allowance
            require(
                hakTokenInstance.allowance(msg.sender, address(this)) >= amount,
                "insufficient allowance"
            );
            // transfer token
            if (
                !hakTokenInstance.transferFrom(
                    msg.sender,
                    address(this),
                    amount
                )
            ) {
                revert("transaction failed");
            }
        } else {
            // unknown token case
            revert("token not supported");
        }

        // update account
        _recalcInterest(token);
        accounts[msg.sender][token].deposit = accounts[msg.sender][token]
            .deposit
            .add(amount);

        // if we reach this, then it's all good
        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount)
        external
        override
        returns (uint256)
    {
        require(amount >= 0, "cannot withdraw a negative value");
        uint256 clientBalance = getBalance(token);

        if (amount == 0) {
            amount = clientBalance;
        }

        require(clientBalance > 0, "no balance");
        require(clientBalance >= amount, "amount exceeds balance");

        // check local contract balance sufficience
        if (token == etherTokenAddress) {
            // eth case
            require(
                address(this).balance >= amount,
                "insuffucient balance in contract"
            );
        } else if (token == hakTokenAddress) {
            // hak case
            IERC20 hakTokenInstance = IERC20(token);
            require(
                hakTokenInstance.balanceOf(address(this)) >= amount,
                "insuffucient balance in contract"
            );
        }

        // update interest size to reduce headache
        _recalcInterest(token);

        uint256 interestSize = accounts[msg.sender][token].interest.add(
            _calcInterest(
                accounts[msg.sender][token].lastInterestBlock,
                accounts[msg.sender][token].deposit
            )
        );

        if (amount <= interestSize) {
            // just deduct the interest
            accounts[msg.sender][token].interest = accounts[msg.sender][token]
                .interest
                .sub(amount);
        } else {
            // set interest to zero
            // and deduct remainder from deposit
            uint256 remainderForDepositPart = amount.sub(interestSize);
            accounts[msg.sender][token].deposit = accounts[msg.sender][token]
                .deposit
                .sub(remainderForDepositPart);
            accounts[msg.sender][token].interest = 0;
        }

        if (token == etherTokenAddress) {
            // eth case
            msg.sender.transfer(amount);
        } else if (token == hakTokenAddress) {
            // hak case
            IERC20 hakTokenInstance = IERC20(token);
            if (!hakTokenInstance.transfer(msg.sender, amount)) {
                revert("transfer failed");
            }
        }

        emit Withdraw(msg.sender, token, amount);
    }

    function borrow(address token, uint256 amount)
        external
        override
        returns (uint256)
    {}

    function repay(address token, uint256 amount)
        external
        payable
        override
        returns (uint256)
    {}

    function liquidate(address token, address account)
        external
        payable
        override
        returns (bool)
    {}

    function getCollateralRatio(address token, address account)
        public
        view
        override
        returns (uint256)
    {}

    function getBalance(address token) public view override returns (uint256) {
        require(
            token == etherTokenAddress || token == hakTokenAddress,
            "token not supported"
        );

        return
            accounts[msg.sender][token]
                .interest
                .add(
                    _calcInterest(
                        accounts[msg.sender][token].lastInterestBlock,
                        accounts[msg.sender][token].deposit
                    )
                )
                .add(accounts[msg.sender][token].deposit);
    }
}
