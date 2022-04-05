'reach 0.1'
'use strict'

import {
  NFT_COST,
  removeFromArray,
  chkValidToks,
  getRNum,
  sendNft,
  defToks,
  addToArray
} from './utils.rsh'

export const main = Reach.App(() => {
  const Owner = Participant('Owner', {
    payToken: Token,
    ready: Fun([], Null),
  })

  const Gashapon = API('Gashapon', {
    insertToken: Fun([UInt], Null),
    turnCrank: Fun([], Null),
    load: Fun([Array(Token, 8)], Array(Token, 8)),
  })

  init()

  Owner.only(() => {
    const payToken = declassify(interact.payToken)
  })

  Owner.publish(payToken)
  const tMap = new Map(Token)
  commit()

  Owner.interact.ready()

  check(balance() === 0)
  Owner.publish()

  const [nftsInMachine, R, toksTkn, loadedAmt] = parallelReduce([
    defToks,
    digest(0),
    0,
    0,
  ])
    .invariant(balance() === 0)
    .while(toksTkn < nftsInMachine.length - 1)
    .paySpec([payToken])
    .api(
      Gashapon.load,
      nftsToLoad => {
        check(nftsToLoad.length <= nftsInMachine.length)
        chkValidToks(nftsToLoad)
        check(loadedAmt < nftsInMachine.length - 1)
      },
      _ => [0, [0, payToken]],
      (nftsToLoad, k) => {
        check(nftsToLoad.length <= nftsInMachine.length)
        chkValidToks(nftsToLoad)
        check(loadedAmt < nftsInMachine.length - 1)
        const newArr = addToArray(nftsInMachine, loadedAmt, nftsToLoad[0])
        const val = [newArr, R, toksTkn, loadedAmt + 1]
        k(nftsToLoad)
        return val
      }
    )
    .api(
      Gashapon.insertToken,
      rNum => {
        const rN = getRNum(rNum, R)
        const nonTakenLength = nftsInMachine.length - toksTkn
        const index = rN % nonTakenLength
        const maxIndex = nonTakenLength - 1
        check(nonTakenLength > 0, 'assume machine has NFTs')
        check(index <= maxIndex, 'assume item is in the bounds of array')
        check(isSome(nftsInMachine[index]), 'assume nft is at location')
        check(NFT_COST == 1)
      },
      _ => [0, [NFT_COST, payToken]],
      (rNum, k) => {
        const rN = getRNum(rNum, R)
        const nonTakenLength = nftsInMachine.length - toksTkn
        const index = rN % nonTakenLength
        const maxIndex = nonTakenLength - 1
        check(nonTakenLength > 0, 'require machine has NFTs')
        check(index <= maxIndex, 'require item is in the bounds of array')
        check(isSome(nftsInMachine[index]), 'require nft is at location')
        const [v, newArr] = removeFromArray(nftsInMachine, index, maxIndex)
        const vSome = [newArr, rN, toksTkn + 1, loadedAmt]
        k(null)
        switch (v) {
          case None:
            assert(true)
          case Some:
            tMap[this] = v
        }
        return vSome
      }
    )
    .api(
      Gashapon.turnCrank,
      () => {
        const user = this
        const userTok = tMap[user]
        check(typeOf(userTok) == Token)
        switch (userTok) {
          case None:
            check(balance() == 0)
          case Some:
            check(balance(userTok) > 0)
        }
      },
      () => [0, [0, payToken]],
      k => {
        const user = this
        const userTok = tMap[user]
        check(typeOf(userTok) == Token)
        const val = [nftsInMachine, R, toksTkn, loadedAmt]
        k(null)
        sendNft(user, userTok)
        return val
      }
    )

  transfer(balance()).to(Owner)
  transfer(balance(payToken), payToken).to(Owner)

  commit()
  exit()
})
