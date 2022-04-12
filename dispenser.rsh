'reach 0.1'
'use strict'

import { dispenserI } from './utils.rsh'

export const main = Reach.App(() => {
  const Machine = Participant('Machine', {
    ready: Fun([Contract], Null),
  })
  const api = API(dispenserI)

  init()
  Machine.publish()
  commit()
  Machine.publish()

  Machine.interact.ready(getContract())

  var [owner, receivedNft] = [Machine, false]
  invariant(balance() == 0)
  while (!receivedNft) {
    commit()
    const [[user], k1] = call(api.setOwner).assume(_ => {
      check(Machine == this)
    })
    check(Machine == this)
    k1(getContract())
    commit()
    const [_, k2] = call(api.turnCrank).assume(() => {
      check(Machine !== this)
      check(owner == this)
    })
    check(Machine !== this)
    check(owner == this)
    k2(null)
    ;[owner, receivedNft] = [user, true]

    continue
  }
  commit()
})
