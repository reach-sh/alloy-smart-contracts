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

const logViews = async (address, lender) => {
  let available, rentPrice, total, rented, renterInfo, lenderInfo;
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
  if (address) {
    if (lender) {
      const [_p, i] = await v.getLender(address);
      lenderInfo = i;
    } else {
      const [_p, i] = await v.getRenter(address);
      renterInfo = i;
    }
  }
  available = fmtAvailable;
  rentPrice = fmtPrice;
  total = fmtTotal;
  rented = fmtRented;
  console.log({
    available,
    rentPrice,
    total,
    rented,
    renterInfo,
    lenderInfo,
  });
};
// initial views after deploy
await logViews();

// list nft's
for (const a of lenderAccounts) {
  await a.tokenAccept(nft.id);
  await stdlib.transfer(accDeployer, a, 100, nft.id);
  const ctc = a.contract(backend, ctcInfo);
  await ctc.a.list();
  await logViews(a.networkAccount.addr, true);
}

const c = await lenderAccounts[2].contract(backend, ctcInfo);
await c.a.delist()
await logViews();

for (const a of renterAccounts) {
  const ctc = a.contract(backend, ctcInfo);
  await ctc.a.rent();
  await logViews(a.networkAccount.addr);
}
