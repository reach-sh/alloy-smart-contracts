'reach 0.1';
'use strict';

export const main = Reach.App(() => {
  const D = Participant('D', {});
  const api = API({
    setTime: Fun([UInt], UInt),
  });

  init();
  D.publish();
  commit();

  const [[t], k] = call(api.setTime)
    .assume(_ => assume(this === D))
    .check(_ => check(this === D));
  k(t);

  commit();

  wait(absoluteTime(t)); // wait rent time

  D.publish();

  // make remote call back to parent and reset renting status

  commit();
  exit();
});
