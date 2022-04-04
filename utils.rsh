'reach 0.1'
'use strict'

export const NUM_OF_NFTS = 8

const mTok = Maybe(Token)
export const NFTs = Array(mTok, NUM_OF_NFTS)

export const nTok = Maybe(Token).None(null)
export const defToks = Array.replicate(NUM_OF_NFTS, nTok)

export const NFT_COST = 1

export const chkValidToks = arr => check(arr.all(i => typeOf(i) == Token))

export const removeFromArray = (arr, i, sz) => {
  const k = sz == 0 ? 0 : sz - 1
  const ip = i % sz
  const newArr = Array.set(arr, ip, arr[k])
  const nullEndArr = Array.set(newArr, k, nTok)
  return nullEndArr
}
