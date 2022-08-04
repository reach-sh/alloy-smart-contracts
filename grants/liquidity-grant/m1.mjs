import { loadStdlib } from '@reach-sh/stdlib';
import * as backend from './build/m1.renter.mjs';

const stdlib = loadStdlib('ALGO');
const bal = stdlib.parseCurrency(1000);
const userAccs = await stdlib.newTestAccounts(2, bal);
const fmtAddr = addr => stdlib.formatAddress(addr);
const fmtNum = n => stdlib.bigNumberToNumber(n);
const wait = async t => {
  console.log('waiting for rent time to pass...');
  await stdlib.waitUntilSecs(stdlib.bigNumberify(t));
};

const accCreator = userAccs[0];
const accRenter = userAccs[1];

const ctcMachine = accCreator.contract(backend);

// deploy contract
await stdlib.withDisconnect(() =>
  ctcMachine.p.Creator({
    name: 'Zeaus',
    symbol: 'ZEUS',
    ready: stdlib.disconnect,
  })
);

const ctcInfo = await ctcMachine.getInfo();

const logViews = async () => {
  const acc = await stdlib.newTestAccount(bal);
  const { v } = acc.contract(backend, ctcInfo);
  const [_a, stats] = await v.stats();
  const [_b, creator] = await v.creator();
  const fmtCreator = fmtAddr(creator);
  const fmtStats = {
    ...stats,
    endRentTime: fmtNum(stats.endRentTime),
    rentPrice: fmtNum(stats.rentPrice),
    owner: fmtAddr(stats.owner),
  };
  const result = {
    creator: fmtCreator,
    stats: fmtStats,
  };
  console.log(result);
  return result
};
console.log('initial state')
await logViews()

// make NFT available to rent from creator
await ctcMachine.a.makeAvailable();
console.log('after making available');
await logViews();

// rent NFT
const ctcRenter = accRenter.contract(backend, ctcInfo);
await ctcRenter.a.rent()
console.log('after being rented');
await logViews();

// end rent
const x = await ctcMachine.v.stats()
const endRentTime = fmtNum(x[1].endRentTime)
await wait(endRentTime);
await ctcMachine.a.endRent();
console.log('after rent ended');
await logViews();

