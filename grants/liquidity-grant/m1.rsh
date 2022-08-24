'reach 0.1';
'use strict';

/* GOAL */
// Demonstrate concept via rentable NFTs that can determine if
// ownership is held for the entire period of use.

const RENT_PRICE = 1_000_000;

const ONE_MINUTE = 60;

const Stats = Struct([
  ['owner', Address],
  ['rentPrice', UInt],
  ['isAvailable', Bool],
  ['endRentTime', UInt],
]);

export const renter = Reach.App(() => {
  const Creator = Participant('Creator', {
    name: Bytes(50),
    symbol: Bytes(10),
    ready: Fun([], Null),
  });
  const api = API({
    makeAvailable: Fun([], Null),
    rent: Fun([], Null),
    endRent: Fun([], Null),
  });
  const V = View({
    creator: Address,
    stats: Stats,
  });

  init();

  Creator.publish();
  Creator.interact.ready();

  V.creator.set(Creator);

  const [isAvailable, renter, rentEndTime] = parallelReduce([false, Creator, 0])
    .define(() => {
      V.stats.set(
        Stats.fromObject({
          owner: rentEndTime > 0 ? renter : Creator,
          rentPrice: RENT_PRICE,
          isAvailable: isAvailable,
          endRentTime: rentEndTime,
        })
      );
      const getTime = () => thisConsensusSecs();
    })
    .invariant(balance() === 0)
    .while(true)
    .api_(api.makeAvailable, () => {
      const now = getTime();
      check(this === Creator, 'is owner');
      check(renter === Creator, 'belongs to creator');
      check(!isAvailable, 'is available to rent');
      return [
        0,
        notify => {
          enforce(now >= rentEndTime, 'is rented');
          notify(null);
          return [true, Creator, 0];
        },
      ];
    })
    .api_(api.rent, () => {
      const now = getTime();
      check(isAvailable, 'is available to rent');
      check(renter !== this, 'is renter');
      return [
        RENT_PRICE,
        notify => {
          const endRentTime = now + ONE_MINUTE;
          transfer(RENT_PRICE).to(Creator);
          notify(null);
          return [false, this, endRentTime];
        },
      ];
    })
    .api_(api.endRent, () => {
      const now = getTime();
      check(this === Creator, 'is creator');
      check(rentEndTime > 0 && !isAvailable, 'is being rented');
      return [
        0,
        notify => {
          enforce(now >= rentEndTime, 'is rented');
          notify(null);
          return [false, Creator, 0];
        },
      ];
    });

  commit();
  exit();
});
