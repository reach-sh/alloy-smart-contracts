'reach 0.1';
'use strict';

const STARTING_RENT_PRICE = 100;

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
  });

  init();

  Creator.publish();
  Creator.interact.ready();

  const [isAvailable, renter, rentEndTime, rentPrice, numOfRenters] =
    parallelReduce([false, Creator, 0, STARTING_RENT_PRICE, 0])
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
            return [true, renter, rentEndTime, rentPrice, numOfRenters];
          },
        ];
      })
      .api_(api.rent, () => {
        check(isAvailable, 'is available to rent');
        check(renter !== this, 'is renter');
        return [
          rentPrice,
          notify => {
            const endRentTime = lastConsensusTime() + 10;
            transfer(rentPrice).to(Creator);
            notify(null);
            return [isAvailable, this, endRentTime, rentPrice, numOfRenters];
          },
        ];
      })
      .define(() => {
        const checkCanEndRent = () => {
          check(rentEndTime > 0, 'is being rented');
          check(lastConsensusTime() >= rentEndTime, 'is rent period up');
        };
      })
      .api_(api.endRent, () => {
        check(this === Creator, 'is creator');
        check(renter !== this, 'is renter');
        checkCanEndRent();
        return [
          0,
          notify => {
            notify(null);
            return [isAvailable, Creator, 0, rentPrice, numOfRenters];
          },
        ];
      });

  commit();
  exit();
});
