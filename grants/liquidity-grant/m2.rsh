'reach 0.1';
'use strict';

const STARTING_RENT_PRICE = 1_000_000;

const ONE_MINUTE = 60; // 60 seconds in a minute
const ONE_HOUR = ONE_MINUTE * 60;
const ONE_DAY = ONE_HOUR * 24

const POOL_SIZE = 20;
const MAX_POOL_INDEX = POOL_SIZE - 1;

const PoolSlot = Struct([
  ['renter', Address],
  ['endRentTime', UInt],
  ['isOpen', Bool],
]);

export const pool = Reach.App(() => {
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

  const defPoolSlot = PoolSlot.fromObject({
    renter: thisAddress,
    endRentTime: 0,
    isOpen: true,
  });

  const Lenders = new Map(UInt);
  const Renters = new Map(UInt);
  const Pool = Array.replicate(POOL_SIZE, defPoolSlot);

  const [rentedNFTs, availableNFTs, totPaid, rentPrice, pool, renterSlot] =
    parallelReduce([0, 0, 0, STARTING_RENT_PRICE, Pool, 0])
      .define(() => {
        const totalNFTs = availableNFTs + rentedNFTs;

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

        V.total.set(totalNFTs);
        V.available.set(availableNFTs);
        V.rentPrice.set(rentPrice);
        V.rented.set(rentedNFTs);
        V.getLender.set(addy => {
          const slot = fromSome(Lenders[addy], 0);
          check(slot <= MAX_POOL_INDEX);
          const slotInfo = pool[slot];
          return slotInfo;
        });
        V.getRenter.set(addy => {
          const slot = fromSome(Renters[addy], 0);
          check(slot <= MAX_POOL_INDEX);
          const slotInfo = pool[slot];
          return slotInfo;
        });
      })
      .invariant(balance(nft) === totalNFTs && balance() === totPaid)
      .while(true)
      .define(() => {
        const lenderSlot = availableNFTs;
      })
      .api_(api.list, () => {
        check(lenderSlot <= MAX_POOL_INDEX, 'array bounds check');
        check(isNone(Lenders[this]), 'is lender');
        check(lenderSlot + 1 <= MAX_POOL_INDEX, 'lenders are full');
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
      .define(() => {
        const getEndRentTime = () => lastConsensusSecs() + ONE_MINUTE;
      })
      .api_(api.rent, () => {
        check(availableNFTs > 0, 'is available');
        check(isNone(Renters[this]), 'is renter');
        const x = availableNFTs - 1;
        const newRentPrice = totalNFTs + x;
        check(renterSlot <= MAX_POOL_INDEX, 'is valid slot');
        const endRentTime = getEndRentTime();
        return [
          handlePmt(rentPrice, 0),
          notify => {
            const updatedPool = pool.set(
              renterSlot,
              PoolSlot.fromObject({
                isOpen: false,
                renter: this,
                endRentTime,
              })
            );
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
      }).define(() => {
        const chkCanReclaim = slotInfo => {
          const now = lastConsensusSecs();
          check(slotInfo.renter !== thisAddress, 'has renter');
          check(!slotInfo.isOpen, 'not open');
          check(slotInfo.endRentTime > 0, 'valid rent time');
          check(now >= slotInfo.endRentTime, 'rent time passed');
        };
      })
      .api_(api.reclaim, () => {
        check(isSome(Lenders[this]), 'is lender');
        const slotToReclaim = fromSome(Lenders[this], 0);
        check(slotToReclaim <= MAX_POOL_INDEX);
        const slotInfo = pool[slotToReclaim];
        chkCanReclaim(slotInfo);
        return [
          handlePmt(0, 0),
          notify => {
            const updatedPool = pool.set(slotToReclaim, defPoolSlot);
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
