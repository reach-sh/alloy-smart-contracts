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

const RESERVE_RATIO = 5; // 1:5 reserve ratio - for every one NFT listed, 5 can be rented
const MAX_RESERVE = 10;

const POOL_SIZE = MAX_RESERVE * RESERVE_RATIO;
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
  ['reserve', UInt],
]);

export const pool = Reach.App(() => {
  const Creator = Participant('Creator', {
    tok: Token,
    ready: Fun([], Null),
  });
  const api = API({
    list: Fun([UInt], Null),
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

  const lenderRange = Tuple(Maybe(UInt), Maybe(UInt));
  const Lenders = new Map(Tuple(lenderRange, Maybe(UInt)));
  const Renters = new Map(Maybe(UInt));
  const Pool = Array.replicate(POOL_SIZE, PoolSlot.fromObject(defPoolSlot));

  const [rentedToks, nextAvailIndex, totPaid, reserveSupply, pool] =
    parallelReduce([0, 0, 0, 0, Pool])
      .define(() => {
        const maxAvailble = reserveSupply * RESERVE_RATIO;
        const availableToks = maxAvailble - rentedToks;
        // rent price is affected based on how many tokens are being rented at any given time
        const rentPrice =
          rentedToks === 0
            ? INITIAL_RENT_PRICE
            : (rentedToks === 1 ? 2 : rentedToks) * INITIAL_RENT_PRICE;
        const totalToks = maxAvailble;
        const getTime = addTime => thisConsensusSecs() + addTime;
        const handlePmt = (netAmt, TokAmt) => [netAmt, [TokAmt, tok]];
        const mkNullEndArr = (p, i) => {
          check(i <= MAX_POOL_INDEX);
          const k = availableToks == 0 ? 0 : availableToks - 1;
          check(k <= MAX_POOL_INDEX);
          const ip = i % availableToks;
          check(ip <= MAX_POOL_INDEX);
          const newArr = Array.set(p, ip, p[k]);
          const nullEndArr = Array.set(
            newArr,
            k,
            PoolSlot.fromObject(defPoolSlot)
          );
          return nullEndArr;
        };
        const getLenderInfo = addy => {
          const thisLender = Lenders[addy];
          const defLenderInfo = [
            [Maybe(UInt).None(), Maybe(UInt).None()],
            Maybe(UInt).None(),
          ];
          if (isNone(thisLender)) {
            return defLenderInfo;
          } else {
            const d = fromSome(thisLender, defLenderInfo);
            return d;
          }
        };
        const getRenterSlot = addy => {
          const thisRenter = Renters[addy];
          if (isNone(thisRenter)) {
            return [Maybe(UInt).None(), PoolSlot.fromObject(defPoolSlot)];
          } else {
            const slot = fromSome(thisRenter, Maybe(UInt).None());
            const slotIndex = fromSome(slot, 0);
            check(slotIndex <= MAX_POOL_INDEX, 'array bounds check');
            const slotInfo = pool[slotIndex];
            return [Maybe(UInt).Some(slotIndex), slotInfo];
          }
        };
        const handleListing = who => {
          const startI = reserveSupply * RESERVE_RATIO;
          check(startI + RESERVE_RATIO - 1 <= MAX_POOL_INDEX, 'array check');
          const slotInfo = PoolSlot.fromObject({
            ...defPoolSlot,
            owner: who,
            isOpen: true,
          });
          // this is gross
          // I bet there is an easier/cleaner way to do this
          // ideally I would like to loop/update the next 5 indexes in one swoop based on the Reserve ratio/starting index
          // currently hardcoded amounts as we know the reserve ratio is 5 and thus have to update the 5 relevent indices
          const p1 = pool.set(startI, slotInfo);
          const p2 = p1.set(startI + 1, slotInfo);
          const p3 = p2.set(startI + 2, slotInfo);
          const p4 = p3.set(startI + 3, slotInfo);
          const p5 = p4.set(startI + 4, slotInfo);
          return p5;
        };

        V.stats.set(
          Stats.fromObject({
            available: availableToks,
            total: totalToks,
            rented: rentedToks,
            totalPaid: totPaid,
            rentPrice,
            reserve: reserveSupply,
          })
        );
        V.getLender.set(addy => {
          const [_, currSlot] = getLenderInfo(addy);
          const s = fromSome(currSlot, 0);
          check(s <= MAX_POOL_INDEX, 'array check');
          return [isSome(currSlot), pool[s]];
        });
        V.getRenter.set(addy => {
          const [i, slotInfo] = getRenterSlot(addy);
          return [isSome(i), slotInfo];
        });
      })
      .invariant(balance(tok) === reserveSupply)
      .invariant(balance() === 0)
      .invariant(maxAvailble === reserveSupply * RESERVE_RATIO)
      .while(true)
      .api_(api.list, rP => {
        check(rentPrice >= rP, 'reserve too high');
        check(isNone(Lenders[this]), 'is lender');
        check(reserveSupply * RESERVE_RATIO <= MAX_POOL_INDEX, 'not available');
        return [
          handlePmt(0, 1),
          notify => {
            Lenders[this] = [
              [
                Maybe(UInt).Some(reserveSupply),
                Maybe(UInt).Some(reserveSupply + RESERVE_RATIO - 1),
              ],
              Maybe(UInt).Some(reserveSupply),
            ];
            const updatedPool = handleListing(this);
            notify(null);
            return [
              rentedToks,
              nextAvailIndex,
              totPaid,
              reserveSupply + 1,
              updatedPool,
            ];
          },
        ];
      })
      .api_(api.delist, () => {
        const now = getTime(0);
        check(reserveSupply > 0, 'token to reclaim');
        check(isSome(Lenders[this]), 'is lender');
        const [[strt, end], s] = getLenderInfo(this);
        check(isSome(s), 'is valid slot');
        const sIndex = fromSome(s, 0);
        check(sIndex <= MAX_POOL_INDEX, 'array check');
        const slotInfo = pool[sIndex];
        check(slotInfo.renter === thisAddress, 'has renter');
        const indexToremove = fromSome(s, 0);
        check(indexToremove <= MAX_POOL_INDEX, 'array bounds check');
        check(isSome(strt) && isSome(end), 'valid owned range');
        const rStart = fromSome(strt, 0);
        const rEnd = fromSome(end, 0);
        check(
          rEnd - (RESERVE_RATIO - 1) === rStart &&
            rStart + (RESERVE_RATIO - 1) <= MAX_POOL_INDEX,
          'valid range'
        );
        return [
          handlePmt(0, 0),
          notify => {
            // this is also gross
            // ideally would like to 'loop' or some equivelent based on the reserve ratio to make this dynamic
            // currently hardcoded as we know the reserve ratio is 5 and thus have to update the 5 relevent indices
            // this currently checks that none of the 'notes' issued buy you are being rented before delisting
            enforce(now >= pool[rStart].endRentTime);
            enforce(now >= pool[rStart + 1].endRentTime);
            enforce(now >= pool[rStart + 2].endRentTime);
            enforce(now >= pool[rStart + 3].endRentTime);
            enforce(now >= pool[rStart + 4].endRentTime);
            const p1 = mkNullEndArr(pool, rStart);
            const p2 = mkNullEndArr(p1, rStart + 1);
            const p3 = mkNullEndArr(p2, rStart + 2);
            const p4 = mkNullEndArr(p3, rStart + 3);
            const p5 = mkNullEndArr(p4, rStart + 4);
            delete Lenders[this];
            notify(null);
            transfer(1, tok).to(this);
            return [rentedToks, nextAvailIndex, totPaid, reserveSupply - 1, p5];
          },
        ];
      })
      .api_(api.rent, () => {
        check(availableToks > 0, 'is available');
        check(nextAvailIndex <= MAX_POOL_INDEX, 'array bounds check');
        const { isOpen, owner } = pool[nextAvailIndex];
        check(isOpen, 'is slot available');
        check(owner !== thisAddress, 'valid owner');
        check(isNone(Renters[this]), 'is renter');
        const endRentTime = getTime(ONE_MINUTE);
        return [
          handlePmt(rentPrice, 0),
          notify => {
            transfer(rentPrice).to(owner);
            const updatedPool = pool.set(
              nextAvailIndex,
              PoolSlot.fromObject({
                owner,
                endRentTime,
                isOpen: false,
                renter: this,
              })
            );
            Renters[this] = Maybe(UInt).Some(nextAvailIndex);
            notify(endRentTime);
            return [
              rentedToks + 1,
              nextAvailIndex + 1,
              totPaid + rentPrice,
              reserveSupply,
              updatedPool,
            ];
          },
        ];
      })
      .api_(api.reclaim, () => {
        check(availableToks <= MAX_POOL_INDEX, 'slot available');
        const now = getTime(0);
        const [_, s] = getLenderInfo(this);
        check(isSome(s), 'is valid slot');
        const fsS = fromSome(s, 0);
        check(fsS <= MAX_POOL_INDEX, 'array check');
        const slotInfo = pool[fsS];
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
            return [
              rentedToks - 1,
              nextAvailIndex,
              totPaid,
              reserveSupply,
              updatedPool,
            ];
          },
        ];
      });
  commit();
  exit();
});
