'reach 0.1'
'use strict'

export const getNftCtc = (arr, i, sz) => {
  const k = sz == 0 ? 0 : sz - 1
  const ip = i % sz
  const ctc = arr[ip]
  const defCtc = Maybe(Contract).None(null)
  const newArr = Array.set(arr, ip, arr[k])
  const nullEndArr = Array.set(newArr, k, defCtc)
  return [ctc, nullEndArr]
}
