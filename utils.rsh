'reach 0.1'
'use strict'

export const NUM_OF_NFTS = 8

const mTok = Maybe(Token)
export const NFTs = Array(mTok, NUM_OF_NFTS)

const nTok = Maybe(Token).None(null)

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

export const assignTok = (tok, user, m, tokens) => {
  switch (tok) {
    case None:
      assert(true)
    case Some:
      const actualToken = tokens.find(t => t == tok)
      switch (actualToken) {
        case None:
          assert(true)
        case Some:
          m[user] = actualToken
      }
  }
}

export const sendNft = (user, m) => {
  const tok = m[user]
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
  digest(N, R, thisConsensusTime(), thisConsensusSecs())
