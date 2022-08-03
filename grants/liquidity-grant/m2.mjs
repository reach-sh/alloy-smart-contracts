import { loadStdlib } from '@reach-sh/stdlib';
import * as backend from './build/m2.pool.mjs';

const stdlib = loadStdlib('ALGO');

const bal = stdlib.parseCurrency(1000);
const accDeployer = await stdlib.newTestAccount(bal);
const lenderAccounts = await stdlib.newTestAccounts(10, bal);
const renterAccounts = await stdlib.newTestAccounts(10, bal);

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
    nft: nft.id,
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
  const [_a, rAvailable] = await v.available();
  const [_b, rRentPrice] = await v.rentPrice();
  const [_c, rTotal] = await v.total();
  const [_d, rRented] = await v.rented();
  const fmtAvailable = fmtNum(rAvailable);
  const fmtPrice = fmtNum(rRentPrice);
  const fmtTotal = fmtNum(rTotal);
  const fmtRented = fmtNum(rRented);
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

// rent NFT's
for (const a of renterAccounts) {
  const ctc = a.contract(backend, ctcInfo);
  await ctc.a.rent();
  await logViews(a);
}

console.log('waiting...')
const slotInfo = await getSlotInfo(lenderAccounts[0]);
await stdlib.waitUntilSecs(slotInfo.endRentTime); // wait until rent period ends
const ctcl1 = lenderAccounts[0].contract(backend, ctcInfo);
const currTime = await stdlib.getNetworkSecs()
console.log('can reclaim:', currTime >= slotInfo.endRentTime);
await ctcl1.a.reclaim()