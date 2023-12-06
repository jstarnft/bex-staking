import { ethers, upgrades } from "hardhat"
import "dotenv/config"

async function main() {
  const newContractName = "BinderContract"
  const proxyAddress = process.env.BINDER_CONTRACT!

  console.log(`Upgrading ${newContractName} contract for: \x1b[32m${proxyAddress}\x1b[0m`)
  await upgradeContract(proxyAddress, newContractName)
  console.log("Upgraded!")
}

async function upgradeContract(proxyAddress: string, newContractName: string) {
  const newContractFactory = await ethers.getContractFactory(newContractName)
  const newContract = await upgrades.upgradeProxy(proxyAddress, newContractFactory)
  return newContract
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });