import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import '@openzeppelin/hardhat-upgrades';
import "dotenv/config"

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    }
  },
  networks: {
    polygon: {
      url: process.env.POLYGON_RPC,
      accounts: [
        process.env.PRIVATE_KEY_ADMIN!, 
      ]
    },
  }
};

export default config;