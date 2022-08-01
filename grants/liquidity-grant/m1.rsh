'reach 0.1';
'use strict';

const STARTING_RENT_PRICE = 1_000_000;
const SECONDS_PER_BLOCK = 9 / 2; // 4.5 seconds per block on Algorand
const ONE_MINUTE = 60 / SECONDS_PER_BLOCK;
const ONE_HOUR = ONE_MINUTE * 60;

export const owner = Reach.App(() => {
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
    owner: Address,
    endRentTime: UInt,
    rentPrice: UInt,
    numOfRenters: UInt,
    isAvailable: Bool,
    creator: Address,
  });

  init();

  Creator.publish();
  Creator.interact.ready();

  V.creator.set(Creator);

  const [
    isAvailable,
    renter,
    startRentTime,
    rentEndTime,
    rentPrice,
    numOfRenters,
  ] = parallelReduce([false, Creator, 0, 0, STARTING_RENT_PRICE, 0])
    .define(() => {
      V.owner.set(rentEndTime > 0 ? renter : Creator);
      V.endRentTime.set(rentEndTime);
      V.rentPrice.set(rentPrice);
      V.numOfRenters.set(numOfRenters);
      V.isAvailable.set(isAvailable);
    })
    .invariant(balance() === 0)
    .while(true)
    .api_(api.makeAvailable, () => {
      check(this === Creator, 'is owner');
      check(!isAvailable, 'is available to rent');
      return [
        0,
        notify => {
          notify(null);
          return [
            true,
            renter,
            startRentTime,
            rentEndTime,
            rentPrice,
            numOfRenters,
          ];
        },
      ];
    })
    .define(() => {
      const now = thisConsensusTime();
    })
    .api_(api.rent, () => {
      check(isAvailable, 'is available to rent');
      check(renter !== this, 'is renter');
      check(now >= rentEndTime, 'rent time is up');
      return [
        rentPrice,
        notify => {
          const endRentTime = now + ONE_HOUR;
          transfer(rentPrice).to(Creator);
          notify(null);
          return [
            isAvailable,
            this,
            now,
            endRentTime,
            rentPrice,
            numOfRenters + 1,
          ];
        },
      ];
    })
    .define(() => {
      const checkCanEndRent = () => {
        check(rentEndTime > 0, 'is being rented');
        check(now >= rentEndTime, 'is rent period up');
      };
    })
    .api_(api.endRent, () => {
      check(this === Creator, 'is creator');
      checkCanEndRent();
      return [
        0,
        notify => {
          notify(null);
          return [isAvailable, Creator, 0, 0, rentPrice, numOfRenters];
        },
      ];
    });

  commit();
  exit();
});
