'reach 0.1';
'use strict';

const STARTING_PACK_COST = 100;
// .000001 ALGO will be .0001 ALGO
const PRICE_INCREASE_MULTIPLE = 100;
const MAX_POINTS_IN_PACK = 10;

export const vendingMachine = Reach.App(() => {
  const Deployer = Participant('Deployer', {
    ready: Fun([], Null),
  });
  const api = API({
    buyPack: Fun([UInt], UInt),
    openPack: Fun([UInt], UInt),
  });
  const view = View({
    packTok: Token,
    costOfPack: UInt,
    packTokSupply: UInt,
    howMuchPaid: UInt,
    getUser: Fun([Address], UInt),
  });

  init();
  Deployer.publish();

  const packTok = new Token({
    name: 'Pack Token1111111111111111111111',
    symbol: 'PACK1111',
    supply: UInt.max,
  });

  
  const Users = new Map(UInt);
  
  const handlePmt = (netTok, nonNetTok) => [netTok, [nonNetTok, packTok]];
  
  view.packTok.set(packTok);
  view.getUser.set(u => fromSome(Users[u], 0));

  Deployer.interact.ready();

  const [R, costOfPack, tokSupply, howMuchPaid] = parallelReduce([
    digest(0),
    STARTING_PACK_COST,
    0,
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
    .paySpec([packTok])
    .define(() => {
      const getNewPackCost = () => {
        const newSupply = tokSupply + 1;
        // ax^2 + bx + c
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
      return [
        handlePmt(costOfPack, 0),
        notify => {
          const rN = getRNum(rNum);
          createUser(this);
          sendPackTok(this);
          const updatedPaidAmt = howMuchPaid + costOfPack;
          const [newSupply, updatedPackCost] = getNewPackCost();
          notify(tokSupply);
          return [rN, updatedPackCost, newSupply, updatedPaidAmt];
        },
      ];
    })
    .define(() => {
      const assignPackPoints = (rNum, user) => {
        const foundUser = Users[user];
        const r = getRNum(rNum);
        const pointsFrmPack = r % MAX_POINTS_IN_PACK + 1;
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
    });

  transfer(balance()).to(Deployer);
  commit();
  exit();
});
