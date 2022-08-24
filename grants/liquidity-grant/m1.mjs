import { loadStdlib } from '@reach-sh/stdlib';
import * as backend from './build/m1.renter.mjs';

const stdlib = loadStdlib('ALGO');
const bal = stdlib.parseCurrency(1000);

const fmtAddr = addr => stdlib.formatAddress(addr);
const fmtNum = n => stdlib.bigNumberToNumber(n);
const wait = async t => {
  console.log('waiting for rent time to pass...');
  await stdlib.waitUntilSecs(stdlib.bigNumberify(t));
};

let ctcInfo, ctcMachine;
const launchNFT = async (makeAvailable = true) => {
  const accDeployer = await stdlib.newTestAccount(bal);
  const ctc = accDeployer.contract(backend);
  // deploy contract
  await stdlib.withDisconnect(() =>
    ctc.p.Creator({
      name: 'Zeaus',
      symbol: 'ZEUS',
      ready: stdlib.disconnect,
    })
  );
  const i = await ctc.getInfo();
  if (makeAvailable) {
    await ctc.a.makeAvailable();
  }
  ctcInfo = i;
  ctcMachine = ctc;
};

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
  return result;
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

// can list, make available, rent, and end rent
const gneralTest = async () => {
  console.log('');
  console.log('General Test Started');
  console.log('');
  await launchNFT();
  await logViews();
  const accRenter = await stdlib.newTestAccount(bal);
  const ctcRenter = accRenter.contract(backend, ctcInfo);
  await ctcRenter.a.rent();
  await logViews();
  const x = await ctcMachine.v.stats();
  const endRentTime = fmtNum(x[1].endRentTime);
  await wait(endRentTime);
  await ctcMachine.a.endRent();
  await logViews();
  console.log('===============');
  console.log('Test Complete');
  console.log('===============');
};

// can NOT end rent before rent time is up
const advTest1 = async () => {
  console.log('');
  console.log('Creator Can NOT End Rent Early');
  console.log('');
  await launchNFT();
  await chkErr('not delist while rented', async () => {
    const accRenter = await stdlib.newTestAccount(bal);
    const ctcRenter = accRenter.contract(backend, ctcInfo);
    await ctcRenter.a.rent();
    await ctcMachine.a.endRent();
  });
  await logViews();
  console.log('===============');
  console.log('Test Complete');
  console.log('===============');
};

// can NOT rent while rented
const advTest2 = async () => {
  console.log('');
  console.log('New Renter Can not rent already rented NFT');
  console.log('');
  await launchNFT();
  await chkErr('not rent while rented', async () => {
    const accRenter = await stdlib.newTestAccount(bal);
    const accRenter2 = await stdlib.newTestAccount(bal);
    const ctcRenter = accRenter.contract(backend, ctcInfo);
    const ctcRenter2 = accRenter2.contract(backend, ctcInfo);
    await ctcRenter.a.rent();
    await ctcRenter2.a.rent();
  });
  await logViews();
  console.log('===============');
  console.log('Test Complete');
  console.log('===============');
};

// renter can NOT make available
const advTest3 = async () => {
  console.log('');
  console.log('Only the creator can make available');
  console.log('');
  await launchNFT(false);
  await chkErr('renter can not make available', async () => {
    const accRenter = await stdlib.newTestAccount(bal);
    const ctcRenter = accRenter.contract(backend, ctcInfo);
    await ctcRenter.a.makeAvailable();
  });
  await logViews();
  console.log('===============');
  console.log('Test Complete');
  console.log('===============');
};

const runTests = async () => {
  await gneralTest();
  await advTest1();
  await advTest2();
  await advTest3();
};

await runTests();
