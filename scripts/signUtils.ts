import { ethers } from "ethers";
import "dotenv/config"

async function signRequest(selector: string, name: string, amount: string, user: string, time: number, signer: ethers.Wallet) {
  const messageHexstring = ethers.solidityPacked(
    ["bytes4", "string", "uint256", "address", "uint256"],
    [selector, name, amount, user, time]
  )
  const messageBytes = ethers.getBytes(messageHexstring)
  const signature = await signer.signMessage(messageBytes)
  return { messageHexstring, signature }
}

(async function () {
  const privateKey = process.env.TEST_PRIVATE_KEY!
  console.log(privateKey)
  const wallet = new ethers.Wallet(privateKey)
  console.log('Signer address:', wallet.address)

  const nowTime = parseInt((Date.now() / 1000).toString())
  console.log('UTC time now:', nowTime)

  const amount = '70000000000000000'
  const user = '0xb54e978a34Af50228a3564662dB6005E9fB04f5a'
  const { messageHexstring, signature } = await signRequest('0x84182811', 'hi', amount, user, nowTime, wallet)

  console.log('Raw message:', messageHexstring)
  console.log('Signature:', signature)
})()

/**
 * 0x
 * 84182811
 * 6869
 * 00000000000000000000000000000000000000000000000000f8b0a10e470000
 * b54e978a34af50228a3564662db6005e9fb04f5a
 * 0000000000000000000000000000000000000000000000000000000065674533
 */