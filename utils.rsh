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

export const removeFromArray = (arr, i, sz) => {
  const k = sz == 0 ? 0 : sz - 1
  const ip = i % sz
  const v = arr[ip]
  const newArr = Array.set(arr, ip, arr[k])
  const nullEndArr = Array.set(newArr, k, nTok)
  return [v, nullEndArr]
}

export const sendNft = (user, tok, tokens) => {
  const foundTok = tokens.find(actualTok => mT(actualTok) == tok)
  check(isSome(foundTok), 'token exist')
  switch (foundTok) {
    case None:
      assert(true)
    case Some:
      check(balance(foundTok) > 0, "ensure there is a token to send")
      transfer(1, foundTok).to(user)
  }
}

export const chkTokBalance = (m, user, tokens) => {
  const userTok = m[user]
  const noUser = typeOf(userTok) == null || isNone(userTok)
  if (noUser) {
    return true
  } else {
    check(isSome(userTok), 'ensure the user has a token with data')
    check(tokens.all(t => typeOf(t) == Token), 'ensure tokens array are all tokens')
    const foundTok = tokens.find(actualTok => mT(actualTok) == userTok)
    check(isSome(foundTok), "ensure found token has data")
    foundTok.match({
      Some: tok => { check(balance(tok) > 0, 'check that there is a valid token for the registered user') },
      None: () => { check(balance() == 0) },
    })
    return true
  }
}


// TODO - Jay recommends XORing these before running the digest function.  But there are 3 types here (uint, int, digest) that don't support being XORed together.
// const getRNum = (N, R) => digest(N^ R, thisConsensusTime(), thisConsensusSecs())

// this would not compile when using thisConsensusTime() and thisConsensusSecs()
// hence the "lastConsensus" things instead
export const getRNum = (N, R) =>
  digest(N, R, lastConsensusTime(), lastConsensusSecs())
