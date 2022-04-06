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
    loadNfts: Fun([], Array(Token, 2)),
  })

  const Gashapon = API('Gashapon', {
    insertToken: Fun([UInt], Null),
    turnCrank: Fun([], Null),
  })

  init()

  Owner.only(() => {
    const payToken = declassify(interact.payToken)
  })
  Owner.publish(payToken)

  const tMap = new Map(Token)

  commit()

  Owner.only(() => {
    const [tok1, tok2] = declassify(interact.loadNfts())
    check(distinct(payToken, tok1, tok2))
  })
  Owner.publish(tok1, tok2).pay([
    [1, tok1],
    [1, tok2],
  ])

  const tokActual = array(Token, [tok1, tok2])

  const mToks = array(Maybe(Token), [mT(tok1), mT(tok2)])

  chkValidToks(tokActual)
  check(mToks.all(i => isSome(i)))
  check(balance() === 0)
  check(tokActual.length == mToks.length, 'ensure token tracking is accurate')
  check(
    tokActual.all(t => balance(t) > 0),
    'ensure all tokens are loaded'
  )

  Owner.interact.ready()

  const [nftsInMachine, R, toksTkn] = parallelReduce([mToks, digest(0), 0])
    .invariant(
      balance() === 0 &&
        balance(payToken) / NFT_COST == toksTkn &&
        chkTokBalance(tMap, this, tokActual)
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
      () => {
        const userTok = tMap[this]
        const foundTok = tokActual.find(actualTok => mT(actualTok) == userTok)
        assert(isSome(foundTok))
        switch (foundTok) {
          case None:
            assert(true)
          case Some:
            check(balance(foundTok) > 0, 'chck tok balance')
        }
      },
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
