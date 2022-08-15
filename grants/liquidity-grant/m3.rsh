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
const MAX_RESERVE = 100;

const Stats = Struct([
  ['available', UInt],
  ['total', UInt],
  ['rented', UInt],
  ['totalPaid', UInt],
  ['rentPrice', UInt],
  ['reserve', UInt],
]);

const NextOpenSlot = UInt;
const SlotToCheck = UInt;
const AssignedPos = UInt;
const ReservePrice = UInt;
const Rents = Array(Address, RESERVE_RATIO);
const LenderInfo = Tuple(
  Rents,
  NextOpenSlot,
  SlotToCheck,
  AssignedPos,
  ReservePrice
);
const EndRentTime = UInt;
const RenterInfo = Object({
  endRentTime: EndRentTime,
  lender: Address,
});

export const pool = Reach.App(() => {
  const Creator = Participant('Creator', {
    tok: Token,
    ready: Fun([], Null),
  });
  const api = API({
    list: Fun([ReservePrice], Null),
    delist: Fun([], Null),
    rent: Fun([], UInt),
    endRent: Fun([], UInt),
  });
  const V = View({
    ctcAddress: Address,
    stats: Stats,
    checkIsLender: Fun([Address], LenderInfo),
    checkRenterTime: Fun([Address], Tuple(Bool, RenterInfo)),
  });

  init();

  Creator.only(() => {
    const tok = declassify(interact.tok);
  });
  Creator.publish(tok);

  Creator.interact.ready();

  const thisAddress = getAddress();
  V.ctcAddress.set(thisAddress);

  const defLenderInfo = [
    Array.replicate(RESERVE_RATIO, thisAddress),
    0,
    0,
    0,
    0,
  ];
  const defRenterInfo = {
    endRentTime: 0,
    lender: thisAddress,
  };

  const Lenders = new Map(LenderInfo);
  const Renters = new Map(RenterInfo);
  const queue = Array.replicate(MAX_RESERVE, thisAddress);
  const MAX_QUEUE_INDEX = queue.length - 1;

  const [rentedToks, reserveSupply, totPaid, lendI, rentI, lenderQueue] =
    parallelReduce([0, 0, 0, 0, 0, queue])
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
        const getLRenters = who => {
          const lender = Lenders[who];
          check(isSome(lender), 'is lender');
          const d = fromSome(lender, defLenderInfo);
          return d[0];
        };
        const getLopenSlot = who => {
          const lender = Lenders[who];
          check(isSome(lender), 'is lender');
          const d = fromSome(lender, defLenderInfo);
          return d[1];
        };
        const getLclaimSlot = who => {
          const lender = Lenders[who];
          check(isSome(lender), 'is lender');
          const d = fromSome(lender, defLenderInfo);
          return d[2];
        };
        const getLArrPos = who => {
          const lender = Lenders[who];
          check(isSome(lender), 'is lender');
          const d = fromSome(lender, defLenderInfo);
          return d[3];
        };
        const geLReservePrice = who => {
          const lender = Lenders[who];
          check(isSome(lender), 'is lender');
          const d = fromSome(lender, defLenderInfo);
          return d[4];
        };
        const getLforR = who => {
          check(availableToks > 0, 'is available');
          check(isNone(Renters[who]), 'is renter');
          check(lendI > 0, 'has lender');
          check(rentI < lenderQueue.length, 'array checker');
          const lender = lenderQueue[rentI];
          check(lender !== thisAddress, 'valid lender');
          return lender;
        };
        const getRforL = who => {
          const l = Lenders[who];
          check(isSome(l), 'is lender');
          const [r, os, sc, ap, rp] = fromSome(l, defLenderInfo);
          check(os > 0, 'is renting');
          check(sc <= RESERVE_RATIO - 1, 'array check');
          const renter = r[sc];
          check(renter !== thisAddress, 'valid renter');
          return [renter, [r, os, sc, ap, rp]];
        };
        const mkNullEndArr = i => {
          check(i <= MAX_QUEUE_INDEX);
          const k = availableToks == 0 ? 0 : availableToks - 1;
          check(k <= MAX_QUEUE_INDEX);
          const ip = i % availableToks;
          check(ip <= MAX_QUEUE_INDEX);
          const newArr = Array.set(lenderQueue, ip, lenderQueue[k]);
          const nullEndArr = Array.set(newArr, k, thisAddress);
          return nullEndArr;
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
        V.checkIsLender.set(addy => fromSome(Lenders[addy], defLenderInfo));
        V.checkRenterTime.set(addy => [
          isSome(Renters[addy]),
          fromSome(Renters[addy], defRenterInfo),
        ]);
      })
      .invariant(balance(tok) === reserveSupply)
      .invariant(balance() === 0)
      .invariant(maxAvailble === reserveSupply * RESERVE_RATIO)
      .while(true)
      .api_(api.list, rP => {
        check(isNone(Lenders[this]), 'is lender');
        check(lendI < lenderQueue.length, 'array bounds check');
        return [
          handlePmt(0, 1),
          notify => {
            const x = defLenderInfo.set(3, lendI);
            const lInfo = x.set(4, rP);
            Lenders[this] = lInfo;
            const updatedLArr = lenderQueue.set(lendI, this);
            notify(null);
            return [
              rentedToks,
              reserveSupply + 1,
              totPaid,
              lendI + 1,
              rentI,
              updatedLArr,
            ];
          },
        ];
      })
      .api_(api.delist, () => {
        const lender = Lenders[this];
        check(reserveSupply > 0, 'token to reclaim');
        check(isSome(lender), 'is lender');
        const nextSlot = getLopenSlot(this);
        const assignedPos = getLArrPos(this);
        const slotsClaimed = getLclaimSlot(this);
        check(nextSlot === slotsClaimed, 'reclaimed all toks');
        const newLendArr = mkNullEndArr(assignedPos);
        return [
          handlePmt(0, 0),
          notify => {
            delete Lenders[this];
            notify(null);
            transfer(1, tok).to(this);
            return [
              rentedToks,
              reserveSupply - 1,
              totPaid,
              lendI,
              rentI,
              newLendArr,
            ];
          },
        ];
      })
      .api_(api.rent, () => {
        const lender = getLforR(this);
        const endRentTime = getTime(ONE_MINUTE);
        const renters = getLRenters(lender);
        const nextSlot = getLopenSlot(lender);
        const assignedPos = getLArrPos(lender);
        const slotsClaimed = getLclaimSlot(lender);
        const reservePrice = geLReservePrice(lender);
        check(nextSlot + 1 <= RESERVE_RATIO, 'valid range');
        check(rentPrice >= reservePrice, 'reserve too high');
        const isLenderSpent = nextSlot + 1 === RESERVE_RATIO;
        return [
          handlePmt(rentPrice, 0),
          notify => {
            transfer(rentPrice).to(lender);
            const updatedRenters = renters.set(nextSlot, this);
            Lenders[lender] = [
              updatedRenters,
              nextSlot + 1,
              slotsClaimed,
              assignedPos,
              reservePrice,
            ];
            Renters[this] = {
              endRentTime,
              lender,
            };
            notify(endRentTime);
            return [
              rentedToks + 1,
              reserveSupply,
              totPaid + rentPrice,
              lendI,
              isLenderSpent ? rentI + 1 : rentI,
              lenderQueue,
            ];
          },
        ];
      })
      .api_(api.endRent, () => {
        const now = getTime(0);
        const [renter, [r, os, sc, ap, rp]] = getRforL(this);
        const rInfo = fromSome(Renters[renter], defRenterInfo);
        check(sc + 1 <= RESERVE_RATIO, 'too many');
        return [
          handlePmt(0, 0),
          notify => {
            enforce(now >= rInfo.endRentTime, 'rent time passed');
            Lenders[this] = [r, os, sc + 1, ap, rp];
            notify(sc + 1);
            return [
              rentedToks - 1,
              reserveSupply,
              totPaid,
              lendI,
              rentI,
              lenderQueue,
            ];
          },
        ];
      });
  commit();
  exit();
});
