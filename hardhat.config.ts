import { task } from "hardhat/config";
import "@nomiclabs/hardhat-waffle";

import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.address);
  }
});

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.7.0",
  networks: {
    // hardhat: {
    //   initialBaseFeePerGas: 0,
    // },
    goerli: {
      url: "https://eth-goerli.alchemyapi.io/v2/" + process.env.ALCHEMY_API_KEY,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
};
