'reach 0.1'
'use strict'

export const NUM_OF_NFTS = 20

const mTok = Maybe(Token)
export const NFTs = Array(mTok, NUM_OF_NFTS)

const nTok = Maybe(Token).None(null)
export const defToks = Array.replicate(NUM_OF_NFTS, nTok)

export const NFT_COST = 1

export const mT = tok => Maybe(Token).Some(tok)

export const chkValidToks = arr => check(arr.all(i => typeOf(i) == Token))

export const getNftCtc = (arr, i, sz) => {
  const k = sz == 0 ? 0 : sz - 1
  const ip = i % sz
  const ctc = arr[ip]
  const defCtc = getContract()
  const newArr = Array.set(arr, ip, arr[k])
  const nullEndArr = Array.set(newArr, k, defCtc)
  return [ctc, nullEndArr]
}

export const sendNft = (user, tok, tokens) => {
  const foundTok = tokens.find(actualTok => mT(actualTok) == tok)
  check(isSome(foundTok), 'token exist')
  switch (foundTok) {
    case None:
      assert(true)
    case Some:
      check(balance(foundTok) > 0, 'ensure there is a token to send')
      transfer(1, foundTok).to(user)
      check(balance(foundTok) == 0)
  }
}

export const chkTokBalance = (m, tokens) => {
  return m.all(t => {
    check(typeOf(t) == Token, 'ensure the user has a token')
    check(
      tokens.all(tkn => typeOf(tkn) == Token),
      'ensure tokens array are all tokens'
    )
    check(tokens.includes(t))
    const foundTok = tokens.find(actualTok => actualTok == t)
    switch (foundTok) {
      case Some:
        return balance(foundTok) > 0
      case None:
        return balance() == 0
    }
  })
}

export const chkCtcValid = ctc =>
  check(
    typeOf(ctc) == Contract && ctc !== getContract(),
    'could be invalid contract'
  )

export const dispenserI = {
  setOwner: Fun([Address], Contract),
  turnCrank: Fun([], Null),
}


// TODO - Jay recommends XORing these before running the digest function.  But there are 3 types here (uint, int, digest) that don't support being XORed together.
// const getRNum = (N, R) => digest(N^ R, thisConsensusTime(), thisConsensusSecs())

// this would not compile when using thisConsensusTime() and thisConsensusSecs()
// hence the "lastConsensus" things instead
export const getRNum = (N, R) =>
  digest(N, R, lastConsensusTime(), lastConsensusSecs())
