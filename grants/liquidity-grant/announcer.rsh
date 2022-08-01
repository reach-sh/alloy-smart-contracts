'reach 0.1';
'use strict';

const Renter = Address

export const main = Reach.App(() => {
  const Deployer = Participant('Deployer', { ready: Fun([], Null) });
  const A = API({
    announce: Fun([Renter], Null),
  });
  const N = Events({
    Announce: [Renter],
  });
  init();
  Deployer.publish();
  Deployer.interact.ready();
  const [] = parallelReduce([])
    .while(true)
    .invariant(balance() == 0, 'zero balance')
    .api_(A.announce, r => {
      return [
        0,
        k => {
          k(null);
          N.Announce(r);
          return [];
        },
      ];
    });
  commit();
});
