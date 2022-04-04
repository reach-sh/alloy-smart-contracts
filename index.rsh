'reach 0.1'
'use strict'

import {
  NFTs,
  NFT_COST,
  removeFromArray,
  chkValidToks,
  assignTok,
  getRNum,
  sendNft
} from './utils.rsh'

export const main = Reach.App(() => {
  const Owner = Participant('Owner', {
    payToken: Token,
    ready: Fun([], Null),
    load: Fun([], Array(Token, 8)),
    set: Fun([], NFTs),
  })

  const Gashapon = API('Gashapon', {
    insertToken: Fun([UInt], Null),
    turnCrank: Fun([], Null),
  })

  init()

  Owner.only(() => {
    const payToken = declassify(interact.payToken)
    const nfts = declassify(interact.set())
    chkValidToks(nfts)
    const [tok1, tok2, tok3, tok4, tok5, tok6, tok7, tok8] = declassify(interact.load())

    check(distinct(tok1, tok2, tok3, tok4, tok5, tok6, tok7, tok8, payToken))
  })

  Owner.publish(payToken, nfts)
  commit()

  Owner.publish(tok1, tok2, tok3, tok4, tok5, tok6, tok7, tok8).pay([
    [1, tok1],
    [1, tok2],
    [1, tok3],
    [1, tok4],
    [1, tok5],
    [1, tok6],
    [1, tok7],
    [1, tok8],
  ])

  const tokens = array(Token, [tok1, tok2, tok3, tok4, tok5, tok6, tok7, tok8])
  const tMap = new Map(Token)

  commit()

  Owner.publish()
  Owner.interact.ready()

  check(balance() === 0)
  check(
    tokens.all(t => balance(t) > 0),
    'NFTs are loaded'
  )

  const [nftsInMachine, R, toksTkn] = parallelReduce([nfts, digest(0), 0])
    .invariant(balance() === 0)
    .while(toksTkn < nftsInMachine.length - 1)
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
        const vSome = [newArr, rN, toksTkn + 1]
        k(null)
        assignTok(v, this, tMap, tokens)
        return vSome
      }
    )
    .api(
      Gashapon.turnCrank,
      () => {
        const user = this
        check(typeOf(tMap[user]) == Token)
        const userTok = tMap[user]
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
        check(typeOf(tMap[user]) == Token)
        const userTok = tMap[user]
        switch (userTok) {
          case None:
            check(balance() == 0)
          case Some:
            check(balance(userTok) > 0)
        }
        sendNft(user, tMap)
        const val = [nftsInMachine, R, toksTkn]
        k(null)
        return val
      }
    )

  transfer(balance()).to(Owner)
  transfer(balance(payToken), payToken).to(Owner)
  tokens.forEach(tok => transfer(balance(tok), tok).to(Owner))

  commit()
  exit()
})
