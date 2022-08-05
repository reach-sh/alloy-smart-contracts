import { loadStdlib } from '@reach-sh/stdlib';
import * as backend from './build/m2.pool.mjs';

const stdlib = loadStdlib('ALGO');
const bal = stdlib.parseCurrency(1000);

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

const listNft = async (amt = 1) => {
  const lenders = await stdlib.newTestAccounts(amt, bal);
  for (const a of lenders) {
    await a.tokenAccept(nftId);
    await stdlib.transfer(funder, a, 100, nftId);
    const ctc = a.contract(backend, ctcInfo);
    await ctc.a.list();
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

const reclaimNft = async (lenders, w = true) => {
  for (const a of lenders) {
    const ctc = a.contract(backend, ctcInfo);
    const slotInfo = await getSlotInfo(a, true);
    // wait until rent time ends
    if (w) {
      await wait(slotInfo.endRentTime);
    }
    await ctc.a.reclaim();
    await logViews(a, true);
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
  const lenders = await listNft(10);
  await rentNft(10);
  await reclaimNft(lenders);
  await delistNft(lenders);
};

// can NFT's be listed and delisted
const delistTest = async () => {
  await setUp();
  const lenders = await listNft(10);
  await delistNft(lenders);
};

// can NFT's be listed and delisted
const reclaimTest = async () => {
  await setUp();
  const lenders = await listNft(10);
  await rentNft(10);
  await reclaimNft(lenders);
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
    await reclaimNft(lenders, false);
  });
};

// can NOT rent if none are available
const advTest3 = async () => {
  await setUp();
  await chkErr('not rent if none are available', async () => {
    await listNft(1);
    await rentNft(2);
  });
};

const runTests = async () => {
  await generalTest();
  await reclaimTest();
  await delistTest();
  await advTest1();
  await advTest2();
  await advTest3();
};

await runTests();
