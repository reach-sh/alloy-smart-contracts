'reach 0.1'
'use strict'

export const main = Reach.App(() => {
  const Machine = Participant('Machine', {
    ready: Fun([Contract], Null),
    nft: Token,
  })
  const api = API({
    setOwner: Fun([Address], Token),
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

  check(balance(nft) == 1)

  Machine.interact.ready(getContract())

  const [owner, hasTakenNft, hasOwnerBeenSet] = parallelReduce([Machine, false, false])
    .invariant(balance() == 0)
    .while(!hasTakenNft)
    .api(
      api.setOwner,
      newOwner => {
        check(typeOf(newOwner) == Address)
        check(!hasOwnerBeenSet)
      },
      _ => 0,
      (newOwner, notify) => {
        check(typeOf(newOwner) == Address)
        check(!hasOwnerBeenSet)
        notify(nft)
        return [newOwner, hasTakenNft, true]
      }
    )
    .api(
      api.getNft,
      () => {
        check(hasOwnerBeenSet)
        check(owner !== Machine)
        check(balance(nft) == 1)
      },
      () => 0,
      notify => {
        check(balance(nft) == 1)
        check(owner !== Machine)
        check(hasOwnerBeenSet)
        notify(null)
        transfer(1, nft).to(owner)
        return [owner, true, hasOwnerBeenSet]
      }
    )
  transfer(balance()).to(Machine)
  transfer(balance(nft), nft).to(Machine)
  commit()
})
