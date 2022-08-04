'reach 0.1';
'use strict';

const STARTING_RENT_PRICE = 1_000_000;

const RENT_BLOCKS = 50;

const POOL_SIZE = 20;
const MAX_POOL_INDEX = POOL_SIZE - 1;

const PoolSlot = Struct([
  ['renter', Address],
  ['endRentTime', UInt],
  ['isOpen', Bool],
]);

const Stats = Struct([
  ['rentPrice', UInt],
  ['available', UInt],
  ['total', UInt],
  ['rented', UInt],
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

  const defPoolSlot = PoolSlot.fromObject({
    renter: thisAddress,
    endRentTime: 0,
    isOpen: true,
  });

  const Lenders = new Map(Maybe(UInt));
  const Renters = new Map(Maybe(UInt));
  const Pool = Array.replicate(POOL_SIZE, defPoolSlot);

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
      const totalToks = availableToks + rentedToks;
      const rentPrice =
        rentedToks === 0
          ? STARTING_RENT_PRICE
          : rentedToks * STARTING_RENT_PRICE;

      const getTime = addTime => lastConsensusTime() + addTime;
      const handlePmt = (netAmt, TokAmt) => [netAmt, [TokAmt, tok]];
      const mkNullEndArr = i => {
        assert(i <= MAX_POOL_INDEX);
        const k = availableToks == 0 ? 0 : availableToks - 1;
        assert(k <= MAX_POOL_INDEX);
        const ip = i % availableToks;
        assert(ip <= MAX_POOL_INDEX);
        const newArr = Array.set(pool, ip, pool[k]);
        const nullEndArr = Array.set(newArr, k, defPoolSlot);
        return nullEndArr;
      };
      const getSlot = (addy, renter) => {
        const M = renter ? Renters : Lenders;
        if (isNone(M[addy])) {
          return [Maybe(UInt).None(), defPoolSlot];
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
          rentPrice,
          available: availableToks,
          total: totalToks,
          rented: rentedToks,
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
    .invariant(balance() === totPaid)
    .invariant(availableToks <= POOL_SIZE)
    .while(true)
    .define(() => {
      const chkCanList = who => {
        check(isNone(Lenders[who]), 'is lender');
        check(nextAvailIndex <= MAX_POOL_INDEX, 'slot available');
      };
    })
    .api_(api.list, () => {
      chkCanList(this);
      return [
        handlePmt(0, 1),
        notify => {
          Lenders[this] = Maybe(UInt).Some(nextAvailIndex);
          notify(null);
          return [rentedToks, availableToks + 1, totPaid, pool];
        },
      ];
    })
    .define(() => {
      const chkCanDelist = who => {
        check(isSome(Lenders[who]), 'is lender');
        const [slot, _] = getSlot(who, false);
        check(isSome(slot), 'is valid slot');
        const indexToremove = fromSome(slot, 0);
        check(indexToremove <= MAX_POOL_INDEX, 'array bounds check');
        check(availableToks > 0);
        return indexToremove;
      };
    })
    .api_(api.delist, () => {
      const indexToremove = chkCanDelist(this);
      return [
        handlePmt(0, 0),
        notify => {
          const updatedPool = mkNullEndArr(indexToremove);
          delete Lenders[this];
          notify(null);
          transfer(1, tok).to(this);
          return [rentedToks, availableToks - 1, totPaid, updatedPool];
        },
      ];
    })
    .define(() => {
      const chkCanRent = who => {
        check(availableToks > 0, 'is available');
        check(isNone(Renters[who]), 'is renter');
        check(rentedToks <= MAX_POOL_INDEX, 'array bounds check');
        check(pool[rentedToks].isOpen, 'is taken');
      };
    })
    .api_(api.rent, () => {
      chkCanRent(this);
      const endRentTime = getTime(RENT_BLOCKS);
      return [
        handlePmt(rentPrice, 0),
        notify => {
          const updatedPool = pool.set(
            nextRentIndex,
            PoolSlot.fromObject({
              isOpen: false,
              renter: this,
              endRentTime,
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
    .define(() => {
      const chkCanReclaim = who => {
        const now = getTime(0);
        const [slot, slotInfo] = getSlot(who, false);
        check(isSome(slot), 'is valid slot');
        const s = fromSome(slot, 0);
        check(slotInfo.renter !== thisAddress, 'has renter');
        check(!slotInfo.isOpen, 'not open');
        check(slotInfo.endRentTime > 0, 'valid rent time');
        check(now >= slotInfo.endRentTime, 'rent time passed');
        check(availableToks <= MAX_POOL_INDEX, 'slot available');
        return [slotInfo, s];
      };
    })
    .api_(api.reclaim, () => {
      const [slotInfo, slotToReclaim] = chkCanReclaim(this);
      return [
        handlePmt(0, 0),
        notify => {
          const updatedPool = pool.set(slotToReclaim, defPoolSlot);
          delete Renters[slotInfo.renter];
          notify(null);
          return [rentedToks - 1, availableToks + 1, totPaid, updatedPool];
        },
      ];
    });
  commit();
  exit();
});
