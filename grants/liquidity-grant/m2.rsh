'reach 0.1';
'use strict';

const STARTING_RENT_PRICE = 1_000_000;
const POOL_SIZE = 95;
const MAX_POOL_INDEX = POOL_SIZE - 1;

export const pool = Reach.App(() => {
  const PoolSlot = Object({
    renter: Address,
    endRentTime: UInt,
    isOpen: Bool,
  });

  const Creator = Participant('Creator', {
    nft: Token,
    ready: Fun([], Null),
  });
  const api = API({
    list: Fun([], Null),
    delist: Fun([], Null),
    rent: Fun([], UInt),
    reclaim: Fun([], Null),
  });
  const V = View({
    rentPrice: UInt,
    available: UInt,
    total: UInt,
    rented: UInt,
    getLender: Fun([Address], PoolSlot),
    getRenter: Fun([Address], PoolSlot),
  });

  init();

  Creator.only(() => {
    const nft = declassify(interact.nft);
  });
  Creator.publish(nft);

  Creator.interact.ready();

  const thisAddress = getAddress();

  const defPoolSlot = {
    renter: thisAddress,
    endRentTime: 0,
    isOpen: true,
  };

  const Lenders = new Map(UInt);
  const Renters = new Map(UInt);
  const Pool = Array.replicate(POOL_SIZE, defPoolSlot);

  const [rentedNFTs, availableNFTs, totPaid, rentPrice, pool, renterSlot] =
    parallelReduce([0, 0, 0, STARTING_RENT_PRICE, Pool, 1])
      .define(() => {
        const getEndRentTime = () => thisConsensusTime() + 1;
        const handlePmt = (netAmt, NftAmt) => [netAmt, [NftAmt, nft]];
        const mkNullEndArr = i => {
          check(i <= MAX_POOL_INDEX);
          check(availableNFTs <= MAX_POOL_INDEX);
          const k = availableNFTs == 0 ? 0 : availableNFTs - 1;
          check(k <= MAX_POOL_INDEX);
          const ip = i % availableNFTs;
          check(ip <= MAX_POOL_INDEX);
          const newArr = Array.set(pool, ip, pool[k]);
          const nullEndArr = Array.set(newArr, k, defPoolSlot);
          return nullEndArr;
        };

        const totalNFTs = availableNFTs + rentedNFTs;

        V.total.set(totalNFTs);
        V.available.set(availableNFTs);
        V.rentPrice.set(rentPrice);
        V.rented.set(rentedNFTs);
        V.getLender.set(addy => {
          const slot = fromSome(Lenders[addy], 0);
          check(slot <= MAX_POOL_INDEX);
          const slotInfo = pool[slot - 1];
          return slotInfo;
        });
        V.getRenter.set(addy => {
          const slot = fromSome(Renters[addy], 0);
          check(slot <= MAX_POOL_INDEX);
          const slotInfo = pool[slot - 1];
          return slotInfo;
        });
      })
      .invariant(balance(nft) === totalNFTs && balance() === totPaid)
      .while(true)
      .define(() => {
        const lenderSlot = availableNFTs;
        const getLenderSlotIndex = () => {
          if (lenderSlot > 0) {
            check(lenderSlot > 0, 'is valid lender slot');
            return lenderSlot - 1;
          } else {
            return 0;
          }
        };
      })
      .api_(api.list, () => {
        const lenderSlotIndex = getLenderSlotIndex();
        check(lenderSlotIndex <= MAX_POOL_INDEX, 'array bounds check');
        check(isNone(Lenders[this]), 'is lender');
        check(availableNFTs + 1 <= MAX_POOL_INDEX, 'lenders are full');
        return [
          handlePmt(0, 1),
          notify => {
            Lenders[this] = lenderSlot;
            notify(null);
            return [
              rentedNFTs,
              availableNFTs + 1,
              totPaid,
              rentPrice,
              pool,
              renterSlot,
            ];
          },
        ];
      })
      .api_(api.delist, () => {
        const x = Lenders[this];
        const lenderSlotToremove = fromSome(x, 0);
        check(lenderSlotToremove > 0, 'is lender');
        const indexToremove = lenderSlotToremove - 1;
        check(indexToremove <= MAX_POOL_INDEX);
        check(balance(nft) > 0);
        check(availableNFTs > 0);
        return [
          handlePmt(0, 0),
          notify => {
            const updatedPool = mkNullEndArr(indexToremove);
            delete Lenders[this];
            notify(null);
            transfer(1, nft).to(this);
            return [
              rentedNFTs,
              availableNFTs - 1,
              totPaid,
              rentPrice,
              updatedPool,
              renterSlot,
            ];
          },
        ];
      })
      .api_(api.rent, () => {
        check(availableNFTs > 0, 'is available');
        check(isNone(Renters[this]), 'is renter');
        const x = availableNFTs - 1;
        const newRentPrice = totalNFTs + x;
        check(renterSlot > 0, 'is there open slot');
        const renterSlotIndex = renterSlot - 1;
        check(renterSlotIndex <= MAX_POOL_INDEX, 'is valid slot');
        const endRentTime = getEndRentTime();
        return [
          handlePmt(rentPrice, 0),
          notify => {
            const updatedPool = pool.set(renterSlotIndex, {
              isOpen: false,
              renter: this,
              endRentTime,
            });
            Renters[this] = renterSlot;
            notify(endRentTime);
            return [
              rentedNFTs + 1,
              availableNFTs - 1,
              totPaid + rentPrice,
              newRentPrice,
              updatedPool,
              renterSlot + 1,
            ];
          },
        ];
      })
      .define(() => {
        // const now = thisConsensusTime();
      })
      .api_(api.reclaim, () => {
        check(isSome(Lenders[this]), 'is lender');
        const slotToReclaim = fromSome(Lenders[this], 0);
        check(slotToReclaim < MAX_POOL_INDEX);
        const slotInfo = pool[slotToReclaim];
        check(slotInfo.renter !== thisAddress, 'has renter');
        check(!slotInfo.isOpen, 'not open');
        check(slotInfo.endRentTime > 0, 'valid rent time');
        // check(now >= slotInfo.endRentTime, 'can reclaim');
        return [
          handlePmt(0, 0),
          notify => {
            const updatedPool = pool.set(slotToReclaim, {
              renter: thisAddress,
              isOpen: true,
              endRentTime: 0,
            });
            delete Renters[slotInfo.renter];
            notify(null);
            return [
              rentedNFTs - 1,
              availableNFTs + 1,
              totPaid,
              rentPrice,
              updatedPool,
              renterSlot,
            ];
          },
        ];
      });
  commit();
  exit();
});
