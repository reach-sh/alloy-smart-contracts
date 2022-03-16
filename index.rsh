'reach 0.1'
'use strict'

import {
  NFTs,
  defToks,
  NUM_OF_NFTS,
  NFT_COST,
  chkValidToks
} from './utils.rsh'

export const main = Reach.App(() => {
  const Owner = Participant('Owner', {
    payToken: Token,
  })

  const Gashapon = API('Gashapon', {
    load: Fun([NFTs], Null),
    insertToken: Fun([UInt], Null),
  })

  init()

  Owner.only(() => {
    const [payToken] = declassify([interact.payToken])
  })
  Owner.publish(payToken)

  // const getRNum = (N, R, time) => R ^ digest(time) ^ digest(N)
  const getRNum = (N, R) => R + N

  require(balance() === 0)

  const [nftsInMachine, R, tokensTaken] = parallelReduce([defToks, 2, 0])
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
        const val = [NFTsForMachine, R, tokensTaken]
        k(null)
        return val
      }
    )
    .api(
      Gashapon.insertToken,
      rNum => {
        assume(nftsInMachine.length > 0, 'assume machine has NFTs')
        assume(
          rNum <= nftsInMachine.length - 1,
          'assume item is in the bounds of array'
        )
      },
      _ => [0, [NFT_COST, payToken]],
      (rNum, k) => {
        const rN = getRNum(rNum, R)
        require(nftsInMachine.length > 0, 'require machine has NFTs')
        require(rN <=
          nftsInMachine.length - 1, 'require item is in the bounds of array')
        require(isSome(nftsInMachine[rN]), 'require there is an NFT')
        const val = [nftsInMachine, rN, tokensTaken]
        k(null)
        return val
      }
    )

  transfer(balance()).to(Owner)
  transfer(balance(payToken), payToken).to(Owner)

  commit()
  exit()
})
