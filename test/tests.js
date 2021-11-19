const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("bignumber.js");

// hardhat internal testnet chain id
const CHAIN_ID = 31337;
const DECIMALS = BigNumber(18);

function getArgsForEvent(receipt, eventName) {
  for (const event of receipt.events) {
    if (event.event !== eventName) {
      continue
    }
    return event.args
  }
}

async function deployContracts(deployer) {

  const taxPercentageValue = BigNumber(0.025).times(BigNumber(10).pow(DECIMALS));

  // deploy contracts
  const Bank = await ethers.getContractFactory("Bank");
  const bank = await Bank.deploy();

  const TestERC20 = await ethers.getContractFactory("TestERC20");
  const testERC20 = await TestERC20.deploy();

  await bank.deployed();
  await testERC20.deployed();

  return [bank, testERC20]
}

describe("Test", function () {
  it("Should work", async function () {
    const [deployer, user1, user2] = await ethers.getSigners();

    // deploy contracts
    const [bank, testERC20] = await deployContracts(deployer);
  });
});
