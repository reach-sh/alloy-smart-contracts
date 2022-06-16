'reach 0.1';
'use strict';

const STARTING_PACK_COST = 1;
const STARTING_SUPPLY = 1;
const SUPPLY_INCREMENT = 1;

export const vendingMachine = Reach.App(() => {
  const Deployer = Participant('Deployer', {
    ready: Fun([], Null),
  });
  const api = API({
    getPack: Fun([], UInt),
  });
  const view = View({
    packTok: Token,
    costOfPack: UInt,
    packTokSupply: UInt,
  });

  init();
  Deployer.publish();

  const packTok = new Token({
    name: 'Pack Token1111111111111111111111',
    symbol: 'PACK1111',
    supply: UInt.max,
  });
  view.packTok.set(packTok);

  Deployer.interact.ready();

  const [totalSpent, costOfPack, tokSupply] = parallelReduce([
    0,
    STARTING_PACK_COST,
    STARTING_SUPPLY,
  ])
    .define(() => {
      view.costOfPack.set(costOfPack);
      view.packTokSupply.set(tokSupply);
    })
    .invariant(balance() === totalSpent)
    .paySpec([])
    .while(true)
    .define(() => {
      const getNewPackCost = () => pow(tokSupply + SUPPLY_INCREMENT, 2, 10);
      const sendPackTok = user => transfer([0, [1, packTok]]).to(user);
    })
    .api_(api.getPack, () => {
      check(balance(packTok) > 0, 'pack token minted');
      return [
        [costOfPack],
        k => {
          sendPackTok(this);
          const updatedPackCost = getNewPackCost();
          k(tokSupply);
          return [
            totalSpent + costOfPack,
            updatedPackCost,
            tokSupply + SUPPLY_INCREMENT,
          ];
        },
      ];
    });

  transfer(balance()).to(Deployer);
  commit();
  exit();
});
