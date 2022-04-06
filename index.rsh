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
    loadNfts: Fun([], Array(Token, 7)),
  })

  const Gashapon = API('Gashapon', {
    insertToken: Fun([UInt], Null),
    turnCrank: Fun([], Null),
  })

  init()

  Owner.only(() => {
    const payToken = declassify(interact.payToken)
    const [nft1, nft2, nft3, nft4, nft5, nft6, nft7] = declassify(
      interact.loadNfts()
    )
    check(distinct(payToken, nft1, nft2, nft3, nft4, nft5, nft6, nft7))
  })
  Owner.publish(payToken)
  commit()

  Owner.only(() => {
    const [nft8, nft9, nft10, nft11, nft12, nft13, nft14] = declassify(
      interact.loadNfts()
    )
    check(
      distinct(
        payToken,
        nft1,
        nft2,
        nft3,
        nft4,
        nft5,
        nft6,
        nft7,
        nft8,
        nft9,
        nft10,
        nft11,
        nft12,
        nft13,
        nft14
      )
    )
  })

  Owner.publish(nft1, nft2, nft3, nft4, nft5, nft6, nft7)
  commit()
  Owner.publish(nft8, nft9, nft10, nft11, nft12, nft13, nft14)
  commit()

  Owner.pay([
    [1, nft1],
    [1, nft2],
    [1, nft3],
    [1, nft4],
    [1, nft5],
    [1, nft6],
    [1, nft7],
    [1, nft8],
    [1, nft9],
    [1, nft10],
    [1, nft11],
    [1, nft12],
    [1, nft13],
    [1, nft14],
  ])

  const tokActual = array(Token, [
    nft1,
    nft2,
    nft3,
    nft4,
    nft5,
    nft6,
    nft7,
    nft8,
    nft9,
    nft10,
    nft11,
    nft12,
    nft13,
    nft14,
  ])
  const mToks = array(Maybe(Token), [
    mT(nft1),
    mT(nft2),
    mT(nft3),
    mT(nft4),
    mT(nft5),
    mT(nft6),
    mT(nft7),
    mT(nft8),
    mT(nft9),
    mT(nft10),
    mT(nft11),
    mT(nft12),
    mT(nft13),
    mT(nft14),
  ])

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

  const [nftsInMachine, R, toksTkn] = parallelReduce([
    mToks,
    digest(0),
    0,
  ])
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
        check(this !== Owner, 'assume owner cannot get NFT')
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
        check(this !== Owner, 'require owner cannot get NFT')
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
  commit()
  Anybody.publish()

  transfer(balance(payToken), payToken).to(Owner)
  commit()
  Anybody.publish()

  // this is disgusting and doesn't work anyway, was just curious if it would
  // it appears that the mere reference to the tokActual array causes X amount of transactions, where X is the number of items in the array
  const nft1T = tokActual[0]
  const nft2T = tokActual[1]
  const nft3T = tokActual[2]
  const nft4T = tokActual[3]
  const nft5T = tokActual[4]
  const nft6T = tokActual[5]
  const nft7T = tokActual[6]
  transfer(balance(nft1T), nft1T).to(Owner)
  transfer(balance(nft2T), nft2T).to(Owner)
  transfer(balance(nft3T), nft3T).to(Owner)
  transfer(balance(nft4T), nft4T).to(Owner)
  transfer(balance(nft5T), nft5T).to(Owner)
  transfer(balance(nft6T), nft6T).to(Owner)
  transfer(balance(nft7T), nft7T).to(Owner)
  commit()
  Anybody.publish()

   const nft8T = tokActual[7]
   const nft9T = tokActual[8]
   const nft10T = tokActual[9]
   const nft11T = tokActual[10]
   const nft12T = tokActual[11]
   const nft13T = tokActual[12]
   const nft14T = tokActual[13]
   transfer(balance(nft8T), nft8T).to(Owner)
   transfer(balance(nft9T), nft9T).to(Owner)
   transfer(balance(nft10T), nft10T).to(Owner)
   transfer(balance(nft11T), nft11T).to(Owner)
   transfer(balance(nft12T), nft12T).to(Owner)
   transfer(balance(nft13T), nft13T).to(Owner)
   transfer(balance(nft14T), nft14T).to(Owner)
   commit()
   Anybody.publish()

  commit()
  exit()
})
