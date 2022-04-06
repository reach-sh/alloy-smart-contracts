'reach 0.1'
'use strict'

import {
  NFT_COST,
  removeFromArray,
  chkValidToks,
  getRNum,
  sendNft,
  chkTokBalance,
  mT
} from './utils.rsh'

export const main = Reach.App(() => {
  const Owner = Participant('Owner', {
    payToken: Token,
    ready: Fun([], Null),
    loadNfts: Fun([], Array(Token, 4)),
  })

  const Gashapon = API('Gashapon', {
    insertToken: Fun([UInt], Null),
    turnCrank: Fun([], Null),
  })

  init()

  Owner.only(() => {
    const payToken = declassify(interact.payToken)
    const [nft1, nft2, nft3, nft4] = declassify(interact.loadNfts())
    check(distinct(payToken, nft1, nft2, nft3, nft4))
  })
  Owner.publish(payToken, nft1, nft2, nft3, nft4)
  commit()

  Owner.pay([
    [1, nft1],
    [1, nft2],
    [1, nft3],
    [1, nft4],
  ])

  const tokActual = array(Token, [nft1, nft2, nft3, nft4])
  const mToks = array(Maybe(Token), [mT(nft1), mT(nft2), mT(nft3), mT(nft4)])

  chkValidToks(tokActual)
  check(mToks.all(i => isSome(i)))
  check(balance() === 0)
  check(tokActual.length == mToks.length, 'ensure token tracking is accurate')
  check(
    tokActual.all(t => balance(t) > 0),
    'ensure all tokens are loaded'
  )

  const tMap = new Map(Token)
  
  Owner.interact.ready()

  const [nftsInMachine, R, toksTkn] = parallelReduce([mToks, digest(0), 0])
    .invariant(
      balance() === 0 &&
        balance(payToken) / NFT_COST == toksTkn &&
        chkTokBalance(tMap, tokActual)
    )
    .while(toksTkn < nftsInMachine.length)
    .paySpec([payToken])
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
        check(typeOf(tMap[this]) == null, 'assume user is not registers')
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
        const val = [newArr, rN, toksTkn + 1]
        k(null)
        switch (v) {
          case None:
            assert(true)
          case Some:
            check(typeOf(tMap[this]) == null, 'require user is not registered')
            tMap[this] = v
        }
        return val
      }
    )
    .api(
      Gashapon.turnCrank,
      () => [0, [0, payToken]],
      k => {
        const user = this
        const userTok = tMap[user]
        check(isSome(userTok))
        k(null)
        sendNft(user, userTok, tokActual)
        delete tMap[user]
        const val = [nftsInMachine, R, toksTkn]
        return val
      }
    )

  transfer(balance()).to(Owner)
  transfer(balance(payToken), payToken).to(Owner)
  tokActual.forEach(t => transfer(balance(t), t).to(Owner))

  commit()
  exit()
})
