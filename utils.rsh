'reach 0.1'
'use strict'

export const NUM_OF_NFTS = 10

const mTok = Maybe(Token)
export const NFTs = Array(mTok, NUM_OF_NFTS)

export const defTok = Maybe(Token).None(null)
export const defToks = Array.replicate(NUM_OF_NFTS, defTok)

export const NFT_COST = 1

export const chkValidToks = arr => arr.all(i => typeOf(i) == Token)
