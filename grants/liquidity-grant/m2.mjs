import { loadStdlib } from '@reach-sh/stdlib';
import * as backend from './build/m2.pool.mjs';

const stdlib = loadStdlib('ALGO');

const bal = stdlib.parseCurrency(1000);

const accDeployer = await stdlib.newTestAccount(bal);
const lenderAccounts = await stdlib.newTestAccounts(10, bal);
const renterAccounts = await stdlib.newTestAccounts(10, bal);

const fmtAddr = addr => stdlib.formatAddress(addr);
const fmtNum = n => stdlib.bigNumberToNumber(n);
const wait = async t => {
  console.log('waiting for rent time to pass...');
  await stdlib.waitUntilTime(stdlib.bigNumberify(t));
};

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
const [_a, add] = await ctcMachine.v.ctcAddress()
const ctcAddress = fmtAddr(add)

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
    const [_p, [isLender, info]] = await v.getLender(addy);
    return isLender ? fmtInfo(info) : null;
  } else {
    const [_p, [isRenter, info]] = await v.getRenter(addy);
    return isRenter ? fmtInfo(info) : null;
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

// list NFT's
console.log('');
console.log('Listing');
console.log('');
for (const a of lenderAccounts) {
  await a.tokenAccept(nft.id);
  await stdlib.transfer(accDeployer, a, 100, nft.id);
  const ctc = a.contract(backend, ctcInfo);
  await ctc.a.list();
  await logViews(a, true);
}

// rent NFT's
console.log('');
console.log('Renting');
console.log('');
for (const a of renterAccounts) {
  const ctc = a.contract(backend, ctcInfo);
  await ctc.a.rent();
  await logViews(a);
}

// reclaim NFT's
console.log('');
console.log('Reclaiming');
console.log('');
for (const a of lenderAccounts) {
  const ctc = a.contract(backend, ctcInfo);
  const slotInfo = await getSlotInfo(a, true);
  // wait until rent time ends
  await wait(slotInfo.endRentTime);
  await ctc.a.reclaim();
  await logViews(a, true);
}

// delist NFT's
console.log('');
console.log('Delisting');
console.log('');
for (const a of lenderAccounts) {
  const ctc = a.contract(backend, ctcInfo);
  await ctc.a.delist();
  await logViews(a, true);
}
