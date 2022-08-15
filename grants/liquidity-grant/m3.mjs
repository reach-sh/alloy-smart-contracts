import { loadStdlib } from '@reach-sh/stdlib';
import * as backend from './build/m3.pool.mjs';

const stdlib = loadStdlib('ALGO');
const bal = stdlib.parseCurrency(800);

const fmtAddr = addr => stdlib.formatAddress(addr);
const fmtNum = n => stdlib.bigNumberToNumber(n);
const wait = async t => {
  console.log('waiting for rent time to pass...');
  await stdlib.waitUntilSecs(stdlib.bigNumberify(t));
};

const createNFT = async acc =>
  await stdlib.launchToken(acc, `Lightning Zeus (season one)`, `ZEUS`, {
    decimals: 0,
  });

let funder, ctcInfo, nftId;
const setUp = async () => {
  const deployer = await stdlib.newTestAccount(bal);
  const nft = await createNFT(deployer);
  // deploy pool contract
  const ctcMachine = deployer.contract(backend);
  await stdlib.withDisconnect(() =>
    ctcMachine.p.Creator({
      tok: nft.id,
      ready: stdlib.disconnect,
    })
  );
  const i = await ctcMachine.getInfo();
  funder = deployer;
  ctcInfo = i;
  nftId = nft.id;
};

const getSlotInfo = async (a, lender) => {
  const acc = await stdlib.newTestAccount(bal);
  const { v } = acc.contract(backend, ctcInfo);
  const addy = a.networkAccount.addr;
  if (lender) {
    const [_p, d] = await v.checkIsLender(addy);
    const renters = d[0];
    const i = fmtNum(d[2]);
    const renter = renters[i];
    const [_g, [isRenter, t]] = await v.checkRenterTime(fmtAddr(renter));
    return !isRenter ? null : fmtNum(t.endRentTime);
  } else {
    const [_j, [isRenter, t]] = await v.checkRenterTime(addy);
    return !isRenter ? null : fmtNum(t.endRentTime);
  }
};

const logViews = async (a, lender) => {
  const acc = await stdlib.newTestAccount(bal);
  const { v } = acc.contract(backend, ctcInfo);
  const [_a, stats] = await v.stats();
  const fmtAvailable = fmtNum(stats.available);
  const fmtTotal = fmtNum(stats.total);
  const fmtRented = fmtNum(stats.rented);
  const fmtRentPrice = stdlib.formatCurrency(stats.rentPrice);
  const fmtTotalPaid = stdlib.formatCurrency(stats.totalPaid);
  const fmtReserve = fmtNum(stats.reserve);

  let info;
  if (a) {
    info = await getSlotInfo(a, lender);
  }
  const result = {
    reserve: fmtReserve,
    available: fmtAvailable,
    total: fmtTotal,
    rented: fmtRented,
    totalPaid: `${fmtTotalPaid} ALGO`,
    rentPrice: `${fmtRentPrice} ALGO`,
    rentalInfo: info,
  };
  console.log(result);
};

const listNft = async (amt = 1, r = 1) => {
  const lenders = await stdlib.newTestAccounts(amt, bal);
  for (const a of lenders) {
    await a.tokenAccept(nftId);
    await stdlib.transfer(funder, a, 80, nftId);
    const ctc = a.contract(backend, ctcInfo);
    const reserve = stdlib.parseCurrency(r);
    await ctc.a.list(reserve);
    await logViews(a, true);
  }
  return lenders;
};

const rentNft = async (amt = 1) => {
  const renters = await stdlib.newTestAccounts(amt, bal);
  for (const a of renters) {
    const ctc = a.contract(backend, ctcInfo);
    await ctc.a.rent();
    await logViews(a);
  }
  return renters;
};

const reclaimNft = async (acc, w = true) => {
  const ctc = acc.contract(backend, ctcInfo);
  const [_c, ctcAddy] = await ctc.v.ctcAddress();
  const fmtCtcAddy = fmtAddr(ctcAddy);
  const [_p, d] = await ctc.v.checkIsLender(acc.networkAccount.addr);
  const renters = d[0];
  for (const r of renters) {
    const addy = fmtAddr(r);
    if (addy === fmtCtcAddy) return;
    const [_j, [isRenter, t]] = await ctc.v.checkRenterTime(addy);
    const endRentTime = !isRenter ? null : fmtNum(t.endRentTime);
    if (w && endRentTime) {
      await wait(endRentTime);
    }
    await ctc.a.endRent();
  }
};

const delistNft = async lenders => {
  for (const a of lenders) {
    const ctc = a.contract(backend, ctcInfo);
    await ctc.a.delist();
    await logViews(a, true);
  }
};

const chkErr = async (lab, test) => {
  let error = null;
  try {
    await test();
  } catch (err) {
    error = err;
  }
  if (!error) throw new Error(`${lab} should have failed`);
};

// can NFT's be listed, rented, reclaimed, and delisted
const generalTest = async () => {
  await setUp();
  const lenders = await listNft(3);
  await rentNft(10);
  for (const l of lenders) {
    await reclaimNft(l);
  }
  await delistNft(lenders);
};

// can NFT's be listed and delisted
const delistTest = async () => {
  await setUp();
  const lenders = await listNft(8);
  await delistNft(lenders);
};

// can NFT's be listed and reclaimed
const reclaimTest = async () => {
  await setUp();
  const lenders = await listNft(1);
  await rentNft(1);
  for (const l of lenders) {
    await reclaimNft(l);
  }
};

// can NOT delist a currently rented NFT
const advTest1 = async () => {
  await setUp();
  await chkErr('not delist while rented', async () => {
    const lenders = await listNft(1);
    await rentNft(1);
    await delistNft(lenders, false);
  });
};

// can NOT reclaim a rented NFT while rented
const advTest2 = async () => {
  await setUp();
  await chkErr('not reclaim while rented', async () => {
    const lenders = await listNft(1);
    await rentNft(1);
    for (const l of lenders) {
      await reclaimNft(l, false);
    }
  });
};

// can NOT rent if none are available
const advTest3 = async () => {
  await setUp();
  await chkErr('not rent if none are available', async () => {
    await rentNft(2);
  });
};

// can NOT list if reserve to high
const advTest4 = async () => {
  await setUp();
  await chkErr('not rent if reserve to high', async () => {
    await listNft(1, 100);
    await rentNft(1);
  });
};

const runTests = async () => {
  await generalTest();
  await reclaimTest();
  await delistTest();
  await advTest1();
  await advTest2();
  await advTest3();
  await advTest4();
};

await runTests();
