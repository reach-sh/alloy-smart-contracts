'reach 0.1'
'use strict'

import {
  NFTs,
  defToks,
  NUM_OF_NFTS,
  NFT_COST,
  chkValidToks,
  removeFromArray
} from './utils.rsh'

export const main = Reach.App(() => {
  const Owner = Participant('Owner', {
    payToken: Token,
  })

  const Gashapon = API('Gashapon', {
    load: Fun([NFTs], Null),
    insertToken: Fun([UInt], Maybe(Token)),
  })

  init()

  Owner.only(() => {
    const [payToken] = declassify([interact.payToken])
  })
  Owner.publish(payToken)

  // TODO - Jay recommends XORing these before running the digest function.  But there are 3 types here (uint, int, digest) that don't support being XORed together.
  const getRNum = (N, R) => digest(N^ R, thisConsensusTime(), thisConsensusSecs())

  require(balance() === 0)

  const [nftsInMachine, R, toksTkn] = parallelReduce([
    defToks,
    digest(0),
    0,
  ])
    .invariant(balance() === 0)
    .while(nftsInMachine.length > 0)
    .paySpec([payToken])
    .api(
      Gashapon.load,
      NFTsForMachine => {
        assume(this == Owner, 'assume is owner')
        assume(
          NFTsForMachine.length == NUM_OF_NFTS,
          'assume number of NFTs correct'
        )
        assume(chkValidToks(NFTsForMachine), 'assume all items are tokens')
      },
      _ => [0, [0, payToken]],
      (NFTsForMachine, k) => {
        require(this == Owner, 'require is owner')
        require(NFTsForMachine.length ==
          NUM_OF_NFTS, 'require number of NFTs correct')
        require(chkValidToks(NFTsForMachine), 'require all items are tokens')
        const val = [NFTsForMachine, R, toksTkn]
        k(null)
        return val
      }
    )
    .api(
      Gashapon.insertToken,
      rNum => {
        assume(nftsInMachine.length - toksTkn > 0, 'assume machine has NFTs')
        assume(
          rNum <= nftsInMachine.length - 1,
          'assume item is in the bounds of array'
        )
        assume(toksTkn <= nftsInMachine.length)
      },
      _ => [0, [NFT_COST, payToken]],
      (rNum, k) => {
        const rN = getRNum(rNum, R)
        const newR = digest(rN)
        const nonTakenLength = nftsInMachine.length - toksTkn
        const index = rN % nonTakenLength
        const maxIndex = nonTakenLength - 1
        require(nonTakenLength > 0, 'require machine has NFTs')
        require(index <=
          maxIndex, 'require item is in the bounds of array')
        require(isSome(nftsInMachine[index]), 'require there is an NFT')
        require(toksTkn <= nftsInMachine.length)
        const [retrievedTok, newArr] = removeFromArray(
          nftsInMachine,
          index,
          maxIndex
        )
        const val = [newArr, newR, toksTkn + 1]
        k(retrievedTok)
        return val
      }
    )

  transfer(balance()).to(Owner)
  transfer(balance(payToken), payToken).to(Owner)

  commit()
  exit()
})
