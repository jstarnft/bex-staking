import { ethers, upgrades } from "hardhat"
import "dotenv/config"
import { BinderContract, MockUSDT } from "../typechain-types"

async function main() {
  const adminAddress = process.env.ADDRESS_ADMIN!

  const mUSDT = await deployMockUSDT()
  console.log("\x1b[0mMockUSDT deployed to:\x1b[32m", await mUSDT.getAddress())

  const binder = await deployBinder(await mUSDT.getAddress(), adminAddress)
  console.log("\x1b[0mBinder deployed to:\x1b[32m", await binder.getAddress())
}

async function deployMockUSDT() {
  return (await ethers.deployContract("MockUSDT")) as MockUSDT
}

async function deployBinder(tokenAddress: string, backendSigner: string) {
  const binderFactory = await ethers.getContractFactory("BinderContract")
  const binder = await upgrades.deployProxy(binderFactory, [tokenAddress, backendSigner])
  return (binder as unknown as BinderContract)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });