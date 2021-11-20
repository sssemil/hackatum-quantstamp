const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  console.log("Account balance:", (await deployer.getBalance()).toString());

  const Bank = await hre.ethers.getContractFactory("Bank");
  const bank = await Bank.deploy("0xc3F639B8a6831ff50aD8113B438E2Ef873845552", "0xbefeed4cb8c6dd190793b1c97b72b60272f3ea6c");
  await bank.deployed();

  console.log("Bank deployed to:", bank.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
