import { ethers } from "ethers";
import "dotenv/config"

const selector = {
  register: '0x8580974c',
  buy: '0xbad9a87d',
  sell: '0x68670601',
  renew: '0xcb62320d',
}

function nowTime() {
  return parseInt((Date.now() / 1000).toString())
}

async function signBaseRequest(selector: string, name: string, amount: string, user: string, time: number, signer: ethers.Wallet) {
  const messageHexstring = ethers.solidityPacked(
    ["bytes4", "string", "uint256", "address", "uint256"],
    [selector, name, amount, user, time]
  )
  const messageBytes = ethers.getBytes(messageHexstring)
  const signature = await signer.signMessage(messageBytes)
  return { messageHexstring, signature, time }
}

async function signRegister(name: string, user: string, signer: ethers.Wallet) {
  return signBaseRequest(
    selector.register, name, '0', user, nowTime(), signer
  )
}

async function signBuyShare(name: string, shareNum: string, user: string, signer: ethers.Wallet) {
  return signBaseRequest(
    selector.buy, name, shareNum, user, nowTime(), signer
  )
}

async function signSellShare(name: string, shareNum: string, user: string, signer: ethers.Wallet) {
  return signBaseRequest(
    selector.sell, name, shareNum, user, nowTime(), signer
  )
}

async function signRenewOwnership(name: string, tokenAmount: string, user: string, signer: ethers.Wallet) {
  return signBaseRequest(
    selector.renew, name, tokenAmount, user, nowTime(), signer
  )
}


(async function () {
  const privateKey = process.env.PRIVATE_KEY_ADMIN!
  const wallet = new ethers.Wallet(privateKey)
  console.log('Signer address:', wallet.address)

  const amount = '7000000000'
  const user = '0xb54e978a34Af50228a3564662dB6005E9fB04f5a'

  const { messageHexstring, signature, time } = await signRenewOwnership('hi', amount, user, wallet)

  console.log('Raw message:', messageHexstring)
  console.log('Signature:', signature)
  console.log('Timestamp: ', time)
})()

/**
 * 0x
 * cb62320d
 * 6869
 * 00000000000000000000000000000000000000000000000000f8b0a10e470000
 * b54e978a34af50228a3564662db6005e9fb04f5a
 * 0000000000000000000000000000000000000000000000000000000065705d53
 */