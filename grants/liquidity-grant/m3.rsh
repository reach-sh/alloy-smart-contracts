'reach 0.1';
'use strict';

/* GOAL */
// Expand the pooled rentable NFT concept by
// adding the fractional reserve concept and
// incorporating a price discovery mechanism where
// more rental volumes automatically creates higher
// prices which leads to greater yields to the real owners.

const INITIAL_RENT_PRICE = 1_000_000;

const ONE_MINUTE = 60;

const POOL_SIZE = 20;
const MAX_POOL_INDEX = POOL_SIZE - 1;

const PoolSlot = Struct([
  ['owner', Address],
  ['renter', Address],
  ['endRentTime', UInt],
  ['isOpen', Bool],
]);

const Stats = Struct([
  ['available', UInt],
  ['total', UInt],
  ['rented', UInt],
  ['totalPaid', UInt],
  ['rentPrice', UInt],
]);

export const pool = Reach.App(() => {
  const Creator = Participant('Creator', {
    tok: Token,
    ready: Fun([], Null),
  });
  const api = API({
    list: Fun([], Null),
    delist: Fun([], Null),
    rent: Fun([], UInt),
    reclaim: Fun([], Null),
  });
  const V = View({
    ctcAddress: Address,
    stats: Stats,
    getLender: Fun([Address], Tuple(Bool, PoolSlot)),
    getRenter: Fun([Address], Tuple(Bool, PoolSlot)),
  });

  init();

  Creator.only(() => {
    const tok = declassify(interact.tok);
  });
  Creator.publish(tok);

  Creator.interact.ready();

  const thisAddress = getAddress();
  V.ctcAddress.set(thisAddress);

  const defPoolSlot = {
    owner: thisAddress,
    renter: thisAddress,
    endRentTime: 0,
    isOpen: false,
  };

  const Lenders = new Map(Maybe(UInt));
  const Renters = new Map(Maybe(UInt));
  const Pool = Array.replicate(POOL_SIZE, PoolSlot.fromObject(defPoolSlot));

  const [rentedToks, availableToks, totPaid, pool] = parallelReduce([
    0,
    0,
    0,
    Pool,
  ])
    .define(() => {
      // the next available indexes for the pool array are the current respective values
      // i.e. there are 0 available tokens, I list a token,
      // I get assigned index/slot 0 and the availableToks value increments by one
      const nextAvailIndex = availableToks;
      const nextRentIndex = rentedToks;
      // rent price is affected based on how many tokens are being rented at any given time
      const rentPrice =
        rentedToks === 0
          ? INITIAL_RENT_PRICE
          : (rentedToks === 1 ? 2 : rentedToks) * INITIAL_RENT_PRICE;
      const totalToks = availableToks + rentedToks;
      const getTime = addTime => thisConsensusSecs() + addTime;
      const handlePmt = (netAmt, TokAmt) => [netAmt, [TokAmt, tok]];
      const mkNullEndArr = i => {
        assert(i <= MAX_POOL_INDEX);
        const k = availableToks == 0 ? 0 : availableToks - 1;
        assert(k <= MAX_POOL_INDEX);
        const ip = i % availableToks;
        assert(ip <= MAX_POOL_INDEX);
        const newArr = Array.set(pool, ip, pool[k]);
        const nullEndArr = Array.set(
          newArr,
          k,
          PoolSlot.fromObject(defPoolSlot)
        );
        return nullEndArr;
      };
      const getSlot = (addy, renter) => {
        const M = renter ? Renters : Lenders;
        if (isNone(M[addy])) {
          return [Maybe(UInt).None(), PoolSlot.fromObject(defPoolSlot)];
        } else {
          const slot = fromSome(M[addy], Maybe(UInt).None());
          const slotIndex = fromSome(slot, 0);
          check(slotIndex <= MAX_POOL_INDEX, 'array bounds check');
          const slotInfo = pool[slotIndex];
          return [Maybe(UInt).Some(slotIndex), slotInfo];
        }
      };

      V.stats.set(
        Stats.fromObject({
          available: availableToks,
          total: totalToks,
          rented: rentedToks,
          totalPaid: totPaid,
          rentPrice,
        })
      );
      V.getLender.set(addy => {
        const [i, slotInfo] = getSlot(addy, false);
        return [isSome(i), slotInfo];
      });
      V.getRenter.set(addy => {
        const [i, slotInfo] = getSlot(addy, true);
        return [isSome(i), slotInfo];
      });
    })
    .invariant(balance(tok) === totalToks)
    .invariant(balance() === 0)
    .invariant(availableToks <= POOL_SIZE)
    .while(true)
    .api_(api.list, () => {
      check(isNone(Lenders[this]), 'is lender');
      check(nextAvailIndex <= MAX_POOL_INDEX, 'slot available');
      return [
        handlePmt(0, 1),
        notify => {
          Lenders[this] = Maybe(UInt).Some(nextAvailIndex);
          const updatedPool = pool.set(
            nextAvailIndex,
            PoolSlot.fromObject({
              ...defPoolSlot,
              owner: this,
              isOpen: true,
            })
          );
          notify(null);
          return [rentedToks, availableToks + 1, totPaid, updatedPool];
        },
      ];
    })
    .api_(api.delist, () => {
      const now = getTime(0);
      check(availableToks > 0, 'token to reclaim');
      check(isSome(Lenders[this]), 'is lender');
      const [s, slotInfo] = getSlot(this, false);
      check(isSome(s), 'is valid slot');
      check(slotInfo.renter === thisAddress, 'has renter');
      const indexToremove = fromSome(s, 0);
      check(indexToremove <= MAX_POOL_INDEX, 'array bounds check');
      return [
        handlePmt(0, 0),
        notify => {
          enforce(now >= slotInfo.endRentTime, 'is rented');
          const updatedPool = mkNullEndArr(indexToremove);
          delete Lenders[this];
          notify(null);
          transfer(1, tok).to(this);
          return [rentedToks, availableToks - 1, totPaid, updatedPool];
        },
      ];
    })
    .api_(api.rent, () => {
      check(availableToks > 0, 'is available');
      check(nextRentIndex <= MAX_POOL_INDEX, 'array bounds check');
      const { isOpen, owner } = pool[nextRentIndex];
      check(isOpen, 'is slot available');
      check(owner !== thisAddress, 'valid owner');
      check(isNone(Renters[this]), 'is renter');
      const endRentTime = getTime(ONE_MINUTE);
      return [
        handlePmt(rentPrice, 0),
        notify => {
          transfer(rentPrice).to(owner);
          const updatedPool = pool.set(
            nextRentIndex,
            PoolSlot.fromObject({
              owner,
              endRentTime,
              isOpen: false,
              renter: this,
            })
          );
          Renters[this] = Maybe(UInt).Some(nextRentIndex);
          notify(endRentTime);
          return [
            rentedToks + 1,
            availableToks - 1,
            totPaid + rentPrice,
            updatedPool,
          ];
        },
      ];
    })
    .api_(api.reclaim, () => {
      check(availableToks <= MAX_POOL_INDEX, 'slot available');
      const now = getTime(0);
      const [s, slotInfo] = getSlot(this, false);
      check(isSome(s), 'is valid slot');
      check(slotInfo.renter !== thisAddress, 'is being rented');
      const slotIndex = fromSome(s, 0);
      return [
        handlePmt(0, 0),
        notify => {
          enforce(now >= slotInfo.endRentTime, 'rent time passed');
          const updatedPool = pool.set(
            slotIndex,
            PoolSlot.fromObject(defPoolSlot)
          );
          delete Renters[slotInfo.renter];
          notify(null);
          return [rentedToks - 1, availableToks + 1, totPaid, updatedPool];
        },
      ];
    });
  commit();
  exit();
});
