'reach 0.1'
'use strict'

export const NUM_OF_NFTS = 10

const mTok = Maybe(Token)
export const NFTs = Array(mTok, NUM_OF_NFTS)

export const nTok = Maybe(Token).None(null)
export const defToks = Array.replicate(NUM_OF_NFTS, nTok)

export const NFT_COST = 1

export const chkValidToks = arr => arr.all(i => typeOf(i) == Token)

// export const makeArrayThatYouCanDeleteFrom = (ty, len) => {
//   const mty = Maybe(ty)
//   const mt = mty.None()
//   const arr0 = Array.replicate(len, mt)
//   const make = ([sz, arr, k]) => ({
//     popeye: i => {
//       assert(sz > 0)
//       const ip = i % sz
//       const v = fromSome(arr[ip], defTok)
//       const kp = k == 0 ? 0 : k - 1
//       const kv = fromSome(arr[k], defTok)
//       const arrp = Array.set(Array.set(arr, k, mt), ip, kv)
//       return [v, make(sz - 1, arrp, kp)]
//     },
//     pushy: v => {
//       const szp = sz + 1
//       assert(szp < len)
//       const kp = k + 1
//       const arrp = Array.set(arr, kp, mty.Some(v))
//       return make(szp, arrp, kp)
//     },
//   })
//   return make([0, arr0, 0])
// }

export const removeFromArray = (arr, i, sz) => {
  const k = sz == 0 ? 0 : sz - 1
  const ip = i % sz
  const v = arr[ip]
  const nullEndArr = Array.set(arr, k, nTok)
  const newArr = Array.set(nullEndArr, ip, arr[k])
  return [v, newArr]
}
