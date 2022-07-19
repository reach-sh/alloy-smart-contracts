'reach 0.1';
'use strict';

export const main = Reach.App(() => {
  const Deployer = Participant('Deployer', { ready: Fun([], Null) });
  const A = API({
    announce: Fun([Contract], Null),
  });
  const N = Events({
    Announce: [Contract],
  });
  init();
  Deployer.publish();
  Deployer.interact.ready();
  const [] = parallelReduce([])
    .while(true)
    .invariant(balance() == 0, 'zero balance')
    .api_(A.announce, ctc => {
      return [
        0,
        k => {
          k(null);
          N.Announce(ctc);
          return [];
        },
      ];
    });
  commit();
});
