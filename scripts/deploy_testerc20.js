const hre = require("hardhat");

function getArgsForEvent(receipt, eventName) {
  for (const event of receipt.events) {
    if (event.event !== eventName) {
      console.log('ignoring unknown event type ', event.event)
      continue
    }
    return event.args
  }
}

async function mint(testERC20, address, amount) {
  const tx = await testERC20.mint(address, amount);
  const r = await tx.wait();
  console.log(getArgsForEvent(r, "Transfer"));
  const balance = await testERC20.balanceOf(address);
  console.log("balance[\"", address, "\"]", parseInt(balance._hex, 16));
}

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const emilsMetammaskAddress = "0xC8ebBbB947D3Cf502f38c8351a69D89B883aADd4";

  console.log("Deploying contracts with the account:", deployer.address);

  console.log("Account balance:", (await deployer.getBalance()).toString());

  const TestERC20 = await ethers.getContractFactory("TestERC20");
  const testERC20 = await TestERC20.deploy();
  await testERC20.deployed();

  console.log("TestERC20 deployed to:", testERC20.address);

  // mint 
  await mint(testERC20, deployer.address, 1000);
  await mint(testERC20, emilsMetammaskAddress, 1000);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
