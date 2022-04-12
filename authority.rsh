'reach 0.1'
'use strict'

import {
  getRNum,
  NFT_COST,
  getNftCtc,
  chkCtcValid,
  dispenserI
} from './utils.rsh'

export const main = Reach.App(() => {
  const Machine = Participant('Machine', {
    payToken: Token,
    ready: Fun([], Null)
  })
  const api = API({
    load: Fun([Contract], Contract),
    insertToken: Fun([UInt], Contract),
  })

  init()

  Machine.only(() => {
    const payToken = declassify(interact.payToken)
  })
  Machine.publish(payToken)
  commit()

  Machine.publish()
  
  const NUM_OF_NFTS = 9
  const defCtc = getContract()
  const NFT_CTCS = Array.replicate(NUM_OF_NFTS, defCtc)
  
  Machine.interact.ready()

  const handlePmt = amt => [0, [amt, payToken]]
  
  const [nftCtcs, R, toksTkn, loadedIndex] = parallelReduce([
    NFT_CTCS,
    digest(0),
    0,
    0,
  ])
    .invariant(balance() === 0 && balance(payToken) / NFT_COST == toksTkn)
    .while(toksTkn < nftCtcs.length)
    .paySpec([payToken])
    .api(
      api.load,
      _ => {
        check(loadedIndex <= nftCtcs.length - 1)
      },
      _ => handlePmt(0),
      (contract, notify) => {
        check(loadedIndex <= nftCtcs.length - 1)
        const newArr = nftCtcs.set(loadedIndex, contract)
        notify(contract)
        return [newArr, R, toksTkn, loadedIndex + 1]
      }
    )
    .api(
      api.insertToken,
      rNum => {
        const rN = getRNum(rNum, R)
        const nonTakenLength = nftCtcs.length - toksTkn
        const index = rN % nonTakenLength
        const maxIndex = nonTakenLength - 1
        check(index <= loadedIndex, 'assume index is of a loaded ctc')
        const [ctc, newCtcArr] = getNftCtc(nftCtcs, index, maxIndex)
        chkCtcValid(ctc)
        check(newCtcArr.length == nftCtcs.length)
      },
      _ => handlePmt(NFT_COST),
      (rNum, notify) => {
        const rN = getRNum(rNum, R)
        const nonTakenLength = nftCtcs.length - toksTkn
        const index = rN % nonTakenLength
        const maxIndex = nonTakenLength - 1
        check(index <= loadedIndex, 'require index is of a loaded ctc')
        const [ctc, newCtcArr] = getNftCtc(nftCtcs, index, maxIndex)
        chkCtcValid(ctc)
        const dispenserCtc = remote(ctc, dispenserI)
        const userCtc = dispenserCtc.setOwner(this)
        notify(userCtc)
        return [newCtcArr, R, toksTkn + 1, loadedIndex]
      }
    )

  transfer(balance()).to(Machine)
  transfer(balance(payToken), payToken).to(Machine)
  commit()
  Anybody.publish()

  commit()
  exit()
})
