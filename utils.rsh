'reach 0.1'
'use strict'

export const NUM_OF_NFTS = 20

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

// not sure this needs to be dynamic as the array length is specified...but oh well, it's done
export const loadNfts = (arr, k, nfts) => {
  const numOfItems = nfts.length
  const ki = k == 0 ? 0 : k - 1
  check(ki + (numOfItems - 1) <= arr.length - 1)
  if (numOfItems === 8) {
    const arr1 = arr.set(ki, Maybe(Token).Some(nfts[0]))
    const arr2 = arr1.set(ki + 1, Maybe(Token).Some(nfts[1]))
    const arr3 = arr2.set(ki + 2, Maybe(Token).Some(nfts[2]))
    const arr4 = arr3.set(ki + 3, Maybe(Token).Some(nfts[3]))
    const arr5 = arr4.set(ki + 4, Maybe(Token).Some(nfts[4]))
    const arr6 = arr5.set(ki + 5, Maybe(Token).Some(nfts[5]))
    const arr7 = arr6.set(ki + 6, Maybe(Token).Some(nfts[6]))
    return [arr7.set(ki + 7, Maybe(Token).Some(nfts[7])), k + 8]
  }
  if (numOfItems === 7) {
    const arr1 = arr.set(ki, Maybe(Token).Some(nfts[0]))
    const arr2 = arr1.set(ki + 1, Maybe(Token).Some(nfts[1]))
    const arr3 = arr2.set(ki + 2, Maybe(Token).Some(nfts[2]))
    const arr4 = arr3.set(ki + 3, Maybe(Token).Some(nfts[3]))
    const arr5 = arr4.set(ki + 4, Maybe(Token).Some(nfts[4]))
    const arr6 = arr5.set(ki + 5, Maybe(Token).Some(nfts[5]))
    return [arr6.set(ki + 6, Maybe(Token).Some(nfts[6])), k + 7]
  }
  if (numOfItems === 6) {
    const arr1 = arr.set(ki, Maybe(Token).Some(nfts[0]))
    const arr2 = arr1.set(ki + 1, Maybe(Token).Some(nfts[1]))
    const arr3 = arr2.set(ki + 2, Maybe(Token).Some(nfts[2]))
    const arr4 = arr3.set(ki + 3, Maybe(Token).Some(nfts[3]))
    const arr5 = arr4.set(ki + 4, Maybe(Token).Some(nfts[4]))
    return [arr5.set(ki + 5, Maybe(Token).Some(nfts[5])), k + 6]
  }
  if (numOfItems === 5) {
    const arr1 = arr.set(ki, Maybe(Token).Some(nfts[0]))
    const arr2 = arr1.set(ki + 1, Maybe(Token).Some(nfts[1]))
    const arr3 = arr2.set(ki + 2, Maybe(Token).Some(nfts[2]))
    const arr4 = arr3.set(ki + 3, Maybe(Token).Some(nfts[3]))
    return [arr4.set(ki + 4, Maybe(Token).Some(nfts[4])), k + 5]
  }
  if (numOfItems === 4) {
    const arr1 = arr.set(ki, Maybe(Token).Some(nfts[0]))
    const arr2 = arr1.set(ki + 1, Maybe(Token).Some(nfts[1]))
    const arr3 = arr2.set(ki + 2, Maybe(Token).Some(nfts[2]))
    return [arr3.set(ki + 3, Maybe(Token).Some(nfts[3])), k + 4]
  }
  if (numOfItems === 3) {
    const arr1 = arr.set(ki, Maybe(Token).Some(nfts[0]))
    const arr2 = arr1.set(ki + 1, Maybe(Token).Some(nfts[1]))
    return [arr2.set(ki + 2, Maybe(Token).Some(nfts[2])), k + 3]
  }
  if (numOfItems === 2) {
    const arr1 = arr.set(ki, Maybe(Token).Some(nfts[0]))
    return [arr1.set(ki + 1, Maybe(Token).Some(nfts[1])), k + 2]
  }
  if (numOfItems === 1) {
    return [arr.set(ki, Maybe(Token).Some(nfts[0])), k + 1]
  }
  return [arr, k]
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

// this would not compile when using thisConsensusTime() and thisConsensusSecs()
// hence the "lastConsensus" things instead
export const getRNum = (N, R) =>
  digest(N, R, lastConsensusTime(), lastConsensusSecs())
