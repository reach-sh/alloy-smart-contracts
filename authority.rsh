'reach 0.1'
'use strict'

import { getRNum, NFT_COST, getNftCtc, chkCtcValid } from './utils.rsh'

export const main = Reach.App(() => {
  const Machine = Participant('Machine', {
    payToken: Token,
    ready: Fun([], Null),
  })
  const api = API({
    load: Fun([Contract], Contract),
    insertToken: Fun([UInt], Contract),
    turnCrank: Fun([], Tuple(Token, Contract)),
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
  const cMap = new Map(Contract)

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
        const userCtc = cMap[this]
        switch (userCtc) {
          case None:
            assert(true)
          case Some:
            check(typeOf(userCtc) == null, 'assume user is not registered')
        }
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
        const userCtc = cMap[this]
        switch (userCtc) {
          case None:
            assert(true)
          case Some:
            check(typeOf(userCtc) == null, 'assume user is not registered')
        }
        const rN = getRNum(rNum, R)
        const nonTakenLength = nftCtcs.length - toksTkn
        const index = rN % nonTakenLength
        const maxIndex = nonTakenLength - 1
        check(index <= loadedIndex, 'require index is of a loaded ctc')
        const [ctc, newCtcArr] = getNftCtc(nftCtcs, index, maxIndex)
        chkCtcValid(ctc)
        cMap[this] = ctc
        notify(ctc)
        return [newCtcArr, R, toksTkn + 1, loadedIndex]
      }
    )
    .api(
      api.turnCrank,
      () => {
        const ctc = cMap[this]
        check(typeOf(ctc) !== null, 'assume user has inserted token')
        const ctcFromsome = fromSome(ctc, getContract())
        chkCtcValid(ctcFromsome)
      },
      () => handlePmt(0),
      notify => {
        const ctc = cMap[this]
        check(typeOf(ctc) !== null, 'require user has inserted token')
        const ctcFromsome = fromSome(ctc, getContract())
        chkCtcValid(ctcFromsome)
        const dispenserCtc = remote(ctcFromsome, {
          setOwner: Fun([Address], Token),
          getNft: Fun([], Null),
        })
        const nft = dispenserCtc.setOwner(this)
        delete cMap[this]
        notify([nft, ctcFromsome])
        return [nftCtcs, R, toksTkn, loadedIndex]
      }
    )

  transfer(balance()).to(Machine)
  transfer(balance(payToken), payToken).to(Machine)
  commit()
  Anybody.publish()

  commit()
  exit()
})
