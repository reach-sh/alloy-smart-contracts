'reach 0.1'
'use strict'

export const main = Reach.App(() => {
  const Machine = Participant('Machine', {
    ready: Fun([Contract], Null),
    nft: Token,
  })
  const api = API({
    setOwner: Fun([Address], Address),
    getNft: Fun([], Null),
  })

  init()
  Machine.publish()
  commit()

  Machine.only(() => {
    const nft = declassify(interact.nft)
  })

  Machine.publish(nft)
  commit()
  Machine.pay([[1, nft]])

  Machine.interact.ready(getContract())

  commit()

  const [[owner], k1] = call(api.setOwner).assume(user => {
    check(user == Machine, 'assume user is the machine')
  })
  check(owner == Machine, 'require user is the machine')
  k1(owner)
  commit()

  const [_, k2] = call(api.getNft).assume(() => {
    check(Machine !== this)
    check(owner == this)
  })
  check(Machine !== this)
  check(owner == this)
  transfer(balance(nft), nft).to(this)
  k2(null)

  commit()
})
