import { loadStdlib } from '@reach-sh/stdlib';
import * as backend from './build/m2.pool.mjs';

const stdlib = loadStdlib('ALGO');

const bal = stdlib.parseCurrency(1000);
const accDeployer = await stdlib.newTestAccount(bal);
const lenderAccounts = await stdlib.newTestAccounts(20, bal);
const renterAccounts = await stdlib.newTestAccounts(19, bal);

const fmtAddr = addr => stdlib.formatAddress(addr);
const fmtNum = n => stdlib.bigNumberToNumber(n);

const nft = await stdlib.launchToken(
  accDeployer,
  `Lightning Zeus (season one)`,
  `ZEUS`,
  {
    decimals: 0,
  }
);

// deploy pool contract
const ctcMachine = accDeployer.contract(backend);
await stdlib.withDisconnect(() =>
  ctcMachine.p.Creator({
    tok: nft.id,
    ready: stdlib.disconnect,
  })
);
const ctcInfo = await ctcMachine.getInfo();

const getSlotInfo = async (a, lender) => {
  const acc = await stdlib.newTestAccount(bal);
  const { v } = acc.contract(backend, ctcInfo);
  const addy = a.networkAccount.addr;
  const fmtInfo = i => {
    if (i)
      return {
        ...i,
        renter: fmtAddr(i.renter),
        endRentTime: fmtNum(i.endRentTime),
      };
    return null;
  };
  if (lender) {
    const [_p, i] = await v.getLender(addy);
    return fmtInfo(i);
  } else {
    const [_p, i] = await v.getRenter(addy);
    return fmtInfo(i);
  }
};

const logViews = async (a, lender) => {
  const acc = await stdlib.newTestAccount(bal);
  const { v } = acc.contract(backend, ctcInfo);
  const [_a, stats] = await v.stats();
  const fmtAvailable = fmtNum(stats.available);
  const fmtPrice = fmtNum(stats.rentPrice);
  const fmtTotal = fmtNum(stats.total);
  const fmtRented = fmtNum(stats.rented);
  let info;
  if (a) {
    info = await getSlotInfo(a, lender);
  }
  const result = {
    available: fmtAvailable,
    rentPrice: fmtPrice,
    total: fmtTotal,
    rented: fmtRented,
    info,
  };
  console.log(result);
};
// initial views after deploy
await logViews();

// list NFT's
for (const a of lenderAccounts) {
  await a.tokenAccept(nft.id);
  await stdlib.transfer(accDeployer, a, 100, nft.id);
  const ctc = a.contract(backend, ctcInfo);
  await ctc.a.list();
  await logViews(a, true);
}

// delist NFT
const ctcL1 = lenderAccounts[0].contract(backend, ctcInfo);
await ctcL1.a.delist();

// rent NFT's
for (const a of renterAccounts) {
  const ctc = a.contract(backend, ctcInfo);
  await ctc.a.rent();
  await logViews(a);
}

// reclaim rented NFT
console.log('waiting...');
const slotInfo = await getSlotInfo(lenderAccounts[1], true);
// wait until rent period ends
await stdlib.waitUntilTime(stdlib.bigNumberify(slotInfo.endRentTime));
const ctcl2 = lenderAccounts[1].contract(backend, ctcInfo);
const currTime = await stdlib.getNetworkTime();
console.log({
  currTime: fmtNum(currTime),
  rentEnd: slotInfo.endRentTime,
});
console.log('can reclaim:', currTime >= slotInfo.endRentTime);
await ctcl2.a.reclaim();
