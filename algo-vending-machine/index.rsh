'reach 0.1';
'use strict';

const STARTING_PACK_COST = 100;
// .000001 ALGO will be .0001 ALGO
const PRICE_INCREASE_MULTIPLE = 100;
const MAX_POINTS_IN_PACK = 10;

const R_NUM = UInt;

export const vendingMachine = Reach.App(() => {
  const Deployer = Participant('Deployer', {
    ready: Fun([], Null),
    NFT: Token,
  });
  const api = API({
    load: Fun([R_NUM, UInt], Null),
    buyPack: Fun([R_NUM], UInt),
    openPack: Fun([R_NUM], UInt),
    crank: Fun([R_NUM], Token),
  });
  // views are things you want the frontend to know
  const view = View({
    packTok: Token,
    costOfPack: UInt,
    packTokSupply: UInt,
    howMuchPaid: UInt,
    getUser: Fun([Address], UInt),
    NFT: Token,
  });

  init();
  Deployer.only(() => {
    const nft = declassify(interact.NFT);
  });
  Deployer.publish(nft);

  const packTok = new Token({
    name: Bytes(32).pad('Pack Token'),
    symbol: Bytes(8).pad('PACK'),
    supply: UInt.max,
    decimals: 0,
  });

  const Users = new Map(UInt);

  const handlePmt = (netTok, nonNetTok) => [
    netTok,
    [0, nft],
    [nonNetTok, packTok],
  ];
  view.packTok.set(packTok);
  view.NFT.set(nft);
  view.getUser.set(u => fromSome(Users[u], 0));

  Deployer.interact.ready();

  const [R, costOfPack, tokSupply, howMuchPaid] = parallelReduce([
    digest(0),
    STARTING_PACK_COST,
    1,
    0,
  ])
    .define(() => {
      view.costOfPack.set(costOfPack);
      view.packTokSupply.set(tokSupply);
      view.howMuchPaid.set(howMuchPaid);
      const getRNum = N =>
        digest(N, R, lastConsensusTime(), lastConsensusSecs());
    })
    .invariant(balance() === howMuchPaid)
    .while(true)
    .paySpec([nft, packTok])
    .define(() => {
      const handleLoad = amt => [0, [amt, nft], [0, packTok]];
    })
    .api_(api.load, (rNum, amt) => {
      check(this === Deployer, 'is loader deployer');
      check(balance(nft) + amt <= UInt.max, 'amount is in bounds');
      return [
        handleLoad(amt),
        notify => {
          const rN = getRNum(rNum);
          notify(null);
          return [rN, costOfPack, tokSupply, howMuchPaid];
        },
      ];
    })
    .define(() => {
      const getNewPackCost = () => {
        const newSupply = tokSupply + 1;
        // bonding curve - ax^2 + bx + c
        const newCost =
          pow(mul(newSupply, PRICE_INCREASE_MULTIPLE), 2, 10) +
          mul(2, newSupply) +
          STARTING_PACK_COST;
        return [newSupply, newCost];
      };
      const sendPackTok = user => transfer([0, [1, packTok]]).to(user);
      const createUser = user => {
        if (isNone(Users[user])) {
          Users[user] = 0;
        }
      };
    })
    .api_(api.buyPack, rNum => {
      check(balance(packTok) > 0, 'pack token available');
      check(balance(nft) > 0, 'NFT is available');
      return [
        handlePmt(costOfPack, 0),
        notify => {
          const rN = getRNum(rNum);
          createUser(this);
          sendPackTok(this);
          const updatedPaidAmt = howMuchPaid + costOfPack;
          const [newSupply, updatedPackCost] = getNewPackCost();
          notify(updatedPackCost);
          return [rN, updatedPackCost, newSupply, updatedPaidAmt];
        },
      ];
    })
    .define(() => {
      const assignPackPoints = (rNum, user) => {
        const foundUser = Users[user];
        const r = getRNum(rNum);
        const pointsFrmPack =
          (r %
            (balance(nft) > MAX_POINTS_IN_PACK
              ? MAX_POINTS_IN_PACK
              : balance(nft))) +
          1;
        Users[user] = fromSome(foundUser, 0) + pointsFrmPack;
        return [r, pointsFrmPack];
      };
    })
    .api_(api.openPack, rNum => {
      return [
        handlePmt(0, 1),
        notify => {
          const [r, pointsFromPack] = assignPackPoints(rNum, this);
          notify(pointsFromPack);
          return [r, costOfPack, tokSupply, howMuchPaid];
        },
      ];
    })
    .define(() => {
      const exchangePoints = user => {
        const currentPoints = fromSome(Users[user], 0);
        Users[user] = currentPoints - 1;
        transfer(1, nft).to(user);
      };
    })
    .api_(api.crank, rNum => {
      check(balance(nft) > 0, 'NFT is available');
      check(isSome(Users[this]), 'user exists');
      check(fromSome(Users[this], 0) > 0, 'user has points');
      return [
        handlePmt(0, 0),
        notify => {
          const r = getRNum(rNum);
          exchangePoints(this);
          notify(nft);
          return [r, costOfPack, tokSupply, howMuchPaid];
        },
      ];
    });

  transfer(balance()).to(Deployer);
  commit();
  exit();
});
