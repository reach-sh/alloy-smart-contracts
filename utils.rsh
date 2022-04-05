'reach 0.1'
'use strict'

export const NUM_OF_NFTS = 8

const mTok = Maybe(Token)
export const NFTs = Array(mTok, NUM_OF_NFTS)

const nTok = Maybe(Token).None(null)
export const defToks = Array.replicate(NUM_OF_NFTS, nTok)

export const NFT_COST = 1

export const chkValidToks = arr => check(arr.all(i => typeOf(i) == Token))

export const removeFromArray = (arr, i, sz) => {
  const k = sz == 0 ? 0 : sz - 1
  const ip = i % sz
  const v = arr[ip]
  const newArr = Array.set(arr, ip, arr[k])
  const nullEndArr = Array.set(newArr, k, nTok)
  return [v, nullEndArr]
}

export const addToArray = (arr, k, v) => {
  const kp = k == 0 ? 0 : k + 1
  check(k <= arr.length - 1)
  const arrp = Array.set(arr, kp, Maybe(Token).Some(v))
  return arrp
}

export const sendNft = (user, tok) => {
  switch (tok) {
    case None:
      assert(true)
    case Some:
      transfer(1, tok).to(user)
  }
}

// TODO - Jay recommends XORing these before running the digest function.  But there are 3 types here (uint, int, digest) that don't support being XORed together.
  // const getRNum = (N, R) => digest(N^ R, thisConsensusTime(), thisConsensusSecs())
export const getRNum = (N, R) =>
  digest(N, R, lastConsensusTime(), lastConsensusSecs())
