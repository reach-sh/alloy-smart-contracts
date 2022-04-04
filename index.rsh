'reach 0.1'
'use strict'

import {
  NFTs,
  NFT_COST,
  removeFromArray
} from './utils.rsh'

export const main = Reach.App(() => {
  const Owner = Participant('Owner', {
    payToken: Token,
    ready: Fun([], Null),
    load: Fun([], Array(Token, 8)),
    set: Fun([], NFTs),
  })

  const Gashapon = API('Gashapon', {
    insertToken: Fun([UInt], Token),
  })

  init()

  Owner.only(() => {
    const [payToken] = declassify([interact.payToken])
    const [nfts, [tok1, tok2, tok3, tok4, tok5, tok6, tok7, tok8]] = declassify(
      [interact.set(), interact.load()]
    )
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

  const sendNft = (tok, user) => {
    tMap[user] = tok
    transfer(1, tok).to(user)
  }

  const getRNum = (N, R) =>
    digest(N, R, thisConsensusTime(), thisConsensusSecs())

  check(balance() === 0)
  check(tokens.all(t => balance(t) > 0), "NFTs are loaded")

  const [nftsInMachine, R, toksTkn] = parallelReduce([nfts, digest(0), 0])
    .invariant(balance() === 0)
    .while(toksTkn < nftsInMachine.length)
    .paySpec([payToken])
    .api(
      Gashapon.insertToken,
      rNum => {
        const rN = getRNum(rNum, R)
        const nonTakenLength = nftsInMachine.length - toksTkn
        const index = rN % nonTakenLength
        const maxIndex = nonTakenLength - 1
        check(index <= tokens.length - 1)
        check(nonTakenLength > 0, 'assume machine has NFTs')
        check(index <= maxIndex, 'assume item is in the bounds of array')
        check(balance(tokens[index]) > 0, 'assume contract has NFT')
        check(NFT_COST == 1)
      },
      _ => [0, [NFT_COST, payToken]],
      (rNum, k) => {
        const rN = getRNum(rNum, R)
        const nonTakenLength = nftsInMachine.length - toksTkn
        const index = rN % nonTakenLength
        const maxIndex = nonTakenLength - 1
        check(index <= tokens.length - 1)
        check(nonTakenLength > 0, 'require machine has NFTs')
        check(index <= maxIndex, 'require item is in the bounds of array')
        check(balance(tokens[index]) > 0, 'require contract has NFT')
        const newArr = removeFromArray(nftsInMachine, rN, maxIndex)
        sendNft(tokens[index], this)
        const val = [newArr, rN, toksTkn + 1]
        k(tokens[index])
        return val
      }
    )

  transfer(balance()).to(Owner)
  transfer(balance(payToken), payToken).to(Owner)
  tokens.forEach(tok => transfer(balance(tok), tok).to(Owner))

  commit()
  exit()
})
