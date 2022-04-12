'reach 0.1'
'use strict'

export const NFT_COST = 1

export const getNftCtc = (arr, i, sz) => {
  const k = sz == 0 ? 0 : sz - 1
  const ip = i % sz
  const ctc = arr[ip]
  const defCtc = getContract()
  const newArr = Array.set(arr, ip, arr[k])
  const nullEndArr = Array.set(newArr, k, defCtc)
  return [ctc, nullEndArr]
}

export const chkCtcValid = ctc =>
  check(
    typeOf(ctc) == Contract && ctc !== getContract(),
    'could be invalid contract'
  )

// TODO - Jay recommends XORing these before running the digest function.  But there are 3 types here (uint, int, digest) that don't support being XORed together.
// const getRNum = (N, R) => digest(N^ R, thisConsensusTime(), thisConsensusSecs())

// this would not compile when using thisConsensusTime() and thisConsensusSecs()
// hence the "lastConsensus" things instead
export const getRNum = (N, R) =>
  digest(N, R, lastConsensusTime(), lastConsensusSecs())
