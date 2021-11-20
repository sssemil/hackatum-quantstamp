//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";
import "./libraries/Math.sol";

contract Bank is IBank {
    using DSMath for uint256;

    address private constant etherTokenAddress =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address private priceOracleAddress;
    address private hakTokenAddress;

    // wallet address -> token address -> Account
    mapping(address => mapping(address => Account)) private deposits;
    // wallet address -> Account (this is only ETH debt!)
    mapping(address => Account) private borrowedEth;

    constructor(address _priceOracle, address _hakToken) {
        priceOracleAddress = _priceOracle;
        hakTokenAddress = _hakToken;
    }

    function _calcInterest(uint256 lastInterestBlock, uint256 deposit)
        internal
        view
        returns (uint256)
    {
        if (deposit == 0) return 0;
        uint256 currentBlock = block.number;
        uint256 blocksDiff = currentBlock.sub(lastInterestBlock);
        if (blocksDiff <= 0) return 0;
        uint256 interest = deposit.mul(blocksDiff).mul(3).div(10000);
        return interest;
    }

    function _calcDebtInterest(uint256 lastInterestBlock, uint256 deposit)
        internal
        view
        returns (uint256)
    {
        if (deposit == 0) return 0;
        uint256 currentBlock = block.number;
        uint256 blocksDiff = currentBlock.sub(lastInterestBlock);
        if (blocksDiff <= 0) return 0;
        uint256 interest = deposit.mul(blocksDiff).mul(5).div(10000);
        return interest;
    }

    function _recalcInterest(address token) internal {
        deposits[msg.sender][token].interest = deposits[msg.sender][token]
            .interest
            .add(
                _calcInterest(
                    deposits[msg.sender][token].lastInterestBlock,
                    deposits[msg.sender][token].deposit
                )
            );
        deposits[msg.sender][token].lastInterestBlock = block.number;
    }

    function _recalcDebtInterest() internal {
        borrowedEth[msg.sender].interest = borrowedEth[msg.sender].interest.add(
            _calcDebtInterest(
                borrowedEth[msg.sender].lastInterestBlock,
                borrowedEth[msg.sender].deposit
            )
        );
        borrowedEth[msg.sender].lastInterestBlock = block.number;
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
        deposits[msg.sender][token].deposit = deposits[msg.sender][token]
            .deposit
            .add(amount);

        // if we reach this, then it's all good
        emit Deposit(msg.sender, token, amount);

        return true;
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

        uint256 interestSize = deposits[msg.sender][token].interest.add(
            _calcInterest(
                deposits[msg.sender][token].lastInterestBlock,
                deposits[msg.sender][token].deposit
            )
        );
        deposits[msg.sender][token].interest = interestSize;

        if (amount <= interestSize) {
            // just deduct the interest
            deposits[msg.sender][token].interest = deposits[msg.sender][token]
                .interest
                .sub(amount);
        } else {
            // set interest to zero
            // and deduct remainder from deposit
            uint256 remainderForDepositPart = amount.sub(interestSize);
            deposits[msg.sender][token].deposit = deposits[msg.sender][token]
                .deposit
                .sub(remainderForDepositPart);
            deposits[msg.sender][token].interest = 0;
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

        return amount;
    }

    function borrow(address token, uint256 amount)
        external
        override
        returns (uint256)
    {
        // we only allow ETH borrowing
        require(token == etherTokenAddress, "token not supported");
        require(amount >= 0, "cannot withdraw a negative value");

        // update interest size to reduce headache
        _recalcInterest(token);
        _recalcDebtInterest();

        uint256 currentHakBalance = getBalance(hakTokenAddress);
        uint256 currentHakBalanceInEth = _hakToEth(currentHakBalance);

        if (amount == 0) {
            amount = currentHakBalanceInEth.mul(10000).div(15000).sub(
                _getEthDebtBalance()
            );
        }

        // now check is the user has enough collateral
        // TODO: Disallow collateral withdrawal!?
        require(currentHakBalance > 0, "no collateral deposited");

        uint256 ratio = currentHakBalanceInEth.mul(10000).div(
            _getEthDebtBalance().add(amount)
        );

        require(ratio >= 15000, "borrow would exceed collateral ratio");

        // now check if the bank has enough eth to lend
        require(
            address(this).balance >= amount,
            "insuffucient balance in contract"
        );

        // update account
        _recalcDebtInterest();
        borrowedEth[msg.sender].deposit = borrowedEth[msg.sender].deposit.add(
            amount
        );

        uint256 newCollateral = getCollateralRatio(hakTokenAddress, msg.sender);

        // if we reach this, then it's all good
        emit Borrow(msg.sender, token, amount, newCollateral);

        // now we can send
        if (!msg.sender.send(amount)) {
            revert("transaction failed");
        }

        return newCollateral;
    }

    function repay(address token, uint256 amount)
        external
        payable
        override
        returns (uint256)
    {
        // we only allow ETH borrowing
        require(token == etherTokenAddress, "token not supported");
        if (amount == 0) {
            // max amount then
            amount = _getEthDebtBalance();
        }
        require(amount > 0, "cannot repay zero or less");
        require(_getEthDebtBalance() > 0, "nothing to repay");
        require(msg.value >= amount, "msg.value < amount to repay");
        require(msg.value <= amount, "msg.value > amount to repay");

        uint256 interestSize = borrowedEth[msg.sender].interest.add(
            _calcDebtInterest(
                borrowedEth[msg.sender].lastInterestBlock,
                borrowedEth[msg.sender].deposit
            )
        );
        borrowedEth[msg.sender].interest = interestSize;

        if (amount <= interestSize) {
            // just deduct the interest
            borrowedEth[msg.sender].interest = borrowedEth[msg.sender]
                .interest
                .sub(amount);
        } else {
            // set interest to zero
            // and deduct remainder from deposit
            uint256 remainderForDepositPart = amount.sub(interestSize);
            borrowedEth[msg.sender].deposit = borrowedEth[msg.sender]
                .deposit
                .sub(remainderForDepositPart);
            borrowedEth[msg.sender].interest = 0;
        }

        emit Repay(msg.sender, token, borrowedEth[msg.sender].deposit);
        return borrowedEth[msg.sender].deposit;
    }

    function liquidate(address token, address account)
        external
        payable
        override
        returns (bool)
    {
        // we only allow ETH borrowing
        require(token == hakTokenAddress, "token not supported");
        require(account != msg.sender, "cannot liquidate own position");

        uint256 debtorsRatio = getCollateralRatio(token, account);
        require(debtorsRatio < 15000, "healty position");

        uint256 debtorsDebt = _getEthDebtBalance(account);
        uint256 debtorsBalanceHak = _getBalance(account, hakTokenAddress);

        require(
            debtorsDebt <= msg.value,
            "insufficient ETH sent by liquidator"
        );

        uint256 amountSentBack = msg.value;
        amountSentBack = amountSentBack.sub(debtorsDebt);
        uint256 amountOfCollateral = debtorsBalanceHak;

        borrowedEth[account].deposit = 0;
        borrowedEth[account].interest = 0;
        borrowedEth[account].lastInterestBlock = block.number;

        emit Liquidate(
            msg.sender,
            account,
            token,
            amountOfCollateral, // amount of collateral token which is sent to the liquidator
            amountSentBack // amount of borrowed token that is sent back to the
            // liquidator in case the amount that the liquidator
            // sent for liquidation was higher than the debt of the liquidated account
        );

        // actually transfer now
        IERC20 hakTokenInstance = IERC20(hakTokenAddress);
        // check if there's sufficient balance
        require(
            hakTokenInstance.balanceOf(address(this)) >= debtorsBalanceHak,
            "insufficient balance"
        );
        hakTokenInstance.transfer(msg.sender, debtorsBalanceHak);

        if (!msg.sender.send(amountSentBack)) {
            revert("transaction failed");
        }

        return true;
    }

    function getCollateralRatio(address token, address account)
        public
        view
        override
        returns (uint256)
    {
        require(token == hakTokenAddress, "token not supported");

        if (_getEthDebtBalance(account) == 0) return type(uint256).max;
        uint256 currentHakBalance = _getBalance(account, hakTokenAddress);
        if (currentHakBalance == 0) return 0;
        return
            _hakToEth(currentHakBalance).mul(10000).div(
                _getEthDebtBalance(account)
            );
    }

    function _getBalance(address account, address token)
        internal
        view
        returns (uint256)
    {
        require(
            token == etherTokenAddress || token == hakTokenAddress,
            "token not supported"
        );

        return
            deposits[account][token]
                .interest
                .add(
                    _calcInterest(
                        deposits[account][token].lastInterestBlock,
                        deposits[account][token].deposit
                    )
                )
                .add(deposits[account][token].deposit);
    }

    function getBalance(address token) public view override returns (uint256) {
        return _getBalance(msg.sender, token);
    }

    function _getEthDebtBalance(address account)
        internal
        view
        returns (uint256)
    {
        return
            borrowedEth[account]
                .interest
                .add(
                    _calcDebtInterest(
                        borrowedEth[account].lastInterestBlock,
                        borrowedEth[account].deposit
                    )
                )
                .add(borrowedEth[account].deposit);
    }

    function _getEthDebtBalance() internal view returns (uint256) {
        return _getEthDebtBalance(msg.sender);
    }

    function _hakToEth(uint256 amount) internal view returns (uint256) {
        IPriceOracle priceOracle = IPriceOracle(priceOracleAddress);
        return
            amount.mul(priceOracle.getVirtualPrice(hakTokenAddress)).div(
                1 ether
            );
    }

    function _ethToHak(uint256 amount) internal view returns (uint256) {
        IPriceOracle priceOracle = IPriceOracle(priceOracleAddress);
        return
            amount.div(priceOracle.getVirtualPrice(hakTokenAddress)).mul(
                1 ether
            );
    }
}
