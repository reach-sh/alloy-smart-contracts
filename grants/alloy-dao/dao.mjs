import {loadStdlib} from '@reach-sh/stdlib';
import * as daoContract from './build/dao.main.mjs';
import * as testProposalContract from './build/test-proposal-contract.main.mjs';
const stdlib = loadStdlib(process.env);

const debugLogging = true;
const d = (...args) => {
  if (debugLogging) {
    console.log(...args);
  }
}

const startingBalance = stdlib.parseCurrency(10);
const adminStartingBalance = stdlib.parseCurrency(1000);
const admin = await stdlib.newTestAccount(adminStartingBalance);
const ctcDao = await admin.contract(daoContract);

const govTokenSupply = 1000;
const govTokenDecimals = 0;
const initPoolSize = 500;
const quorumSizeInit = 350;
const deadlineInit = 1000;
const govTokenTotal = govTokenSupply * (Math.pow(10, govTokenDecimals));
const govTokenOptions = {
  decimals: govTokenDecimals,
  supply: govTokenSupply,
};

const govTokenLaunched = await stdlib.launchToken(admin, "testGovToken", "TGT", govTokenOptions);
const govToken = govTokenLaunched.id;


const startMeUp = async (ctc, getInit) => {
  try {
    await ctc.p.Admin({
      getInit: getInit,
      ready: () => {
        d(`The contract is ready...`)
        throw 42;
      },
    });
  } catch (e) {
    if ( e !== 42) {
      throw e;
    }
  }
}
const dao_getInit = () => {
  return [govToken, govTokenTotal, initPoolSize, quorumSizeInit, deadlineInit];
}
const makePropInit = (payer, payee, netAmt, govAmt) => {
  return () => [payer, payee, netAmt, govAmt, govToken, 0, 0];
}


const makeUser = async (ngov) => {
  const u = await stdlib.newTestAccount(startingBalance);
  await u.tokenAccept(govToken);
  await stdlib.transfer(admin, u, ngov, govToken);
  if (stdlib.connector !== "ALGO") {
    u.setGasLimit(5000000);
  }
  return u;
}

const u1 = await makeUser(100);
const u2 = await makeUser(100);
const u3 = await makeUser(100);
const u4 = await makeUser(100);
const u5 = await makeUser(100);

await startMeUp(ctcDao, dao_getInit);

const mcall = async (ctcBackend, ctcIn, user, methodName, args) => {
  const ctc = user.contract(ctcBackend, ctcIn);
  return await ctc.apis[methodName](...args);
}
const dcall = async (user, methodName, args) => {
  return await mcall(daoContract, ctcDao.getInfo(), user, methodName, args);
}

const makePropCtc = async (payee, paymentAmt, govAmt) => {
  const ctcProp = admin.contract(testProposalContract);
  await startMeUp(ctcProp, makePropInit(await ctcDao.getContractAddress(), payee, paymentAmt, govAmt));
  return ctcProp;
}

// Let's give the dao some network token funds.
await dcall(admin, "fund", [stdlib.parseCurrency(500), 0]);



const checkGBalance = async (user, expectedBal) => {
  const actualBal = await user.balanceOf(govToken);
  if (! stdlib.eq(actualBal, expectedBal)) {
    throw `expected balance: ${expectedBal}, actual balance: ${actualBal}`
  }
}
const checkPoor = async (user, threshold_nonparsed, shouldBePoor) => {
  // This isn't a great check.  Users need to pay transaction fees, and balances can change on Algo with rewards, so I can't just check for an expected number.
  const bal = await user.balanceOf();
  const threshold = stdlib.parseCurrency(threshold_nonparsed);
  const isPoor = stdlib.lt(bal,  threshold);
  if (shouldBePoor !== isPoor) {
    throw `user shouldBePoor (${shouldBePoor}) not matched, balance: ${bal}, threshold: ${threshold}`
  }
}


// Test Payment action

await dcall(u1, "propose", [["Payment", [u1.getAddress(), stdlib.parseCurrency(10), 10]]]);

await checkPoor(u1, 15, true);
await checkGBalance(u1, 100);

const pe1 = await ctcDao.events.Log.propose.next();
const p1 = pe1.what[0];

await dcall (u1, "support", [p1, 100]);
await checkPoor(u1, 15, true);
await checkGBalance(u1, 0);
await dcall (u1, "unsupport", [p1]);
await checkPoor(u1, 15, true);
await checkGBalance(u1, 100);
await dcall (u1, "support", [p1, 100]);
await checkPoor(u1, 15, true);
await checkGBalance(u1, 0);
await dcall (u2, "support", [p1, 100]);
await checkPoor(u1, 15, true);
await dcall (u3, "support", [p1, 100]);
await checkPoor(u1, 15, true);
await dcall (u4, "support", [p1, 100]);
const ee1 = await ctcDao.events.Log.executed.next();
await checkPoor(u1, 15, false);
await checkGBalance(u1, 10);
await dcall (u1, "unsupport", [p1]);
await checkGBalance(u1, 110);
await dcall (u2, "unsupport", [p1]);
await dcall (u3, "unsupport", [p1]);
await dcall (u4, "unsupport", [p1]);

await dcall(u1, "unpropose", [p1]);
await dcall(u1, "fund", [stdlib.parseCurrency(10), 10]);




// Test CallContract action

const paymentAmt = stdlib.parseCurrency(40);
const subGovAmt = 0;
const subCtc1 = await makePropCtc(await u1.getAddress(), paymentAmt, subGovAmt);


await dcall(u1, "propose", [["CallContract", [await subCtc1.getInfo(), paymentAmt, subGovAmt, "These bytes really don't matter."]]]);

const pe2 = await ctcDao.events.Log.propose.next();
const p2 = pe2.what[0];

await dcall (u1, "support", [p2, 100]);
await checkPoor(u1, 25, true);
await checkGBalance(u1, 0);
await dcall (u2, "support", [p2, 100]);
await checkPoor(u1, 25, true);
await dcall (u3, "support", [p2, 100]);
await checkPoor(u1, 25, true);
await dcall (u4, "support", [p2, 100]);
const ee2 = await ctcDao.events.Log.executed.next();
await mcall (testProposalContract, subCtc1.getInfo(), admin, "poke", []);
await checkPoor(u1, 25, false);
await checkPoor(u1, 45, true);
await checkGBalance(u1, 0);
await dcall (u1, "unsupport", [p2]);
await checkGBalance(u1, 100);
await dcall (u2, "unsupport", [p2]);
await dcall (u3, "unsupport", [p2]);
await dcall (u4, "unsupport", [p2]);


// Get the second half of funding from the test contract.
await dcall(u5, "propose", [["CallContract", [await subCtc1.getInfo(), stdlib.parseCurrency(0), 0, "pay"]]]);
const pe3 = await ctcDao.events.Log.propose.next();
const p3 = pe3.what[0];

await dcall (u1, "support", [p3, 100]);
await checkPoor(u1, 45, true);
await checkGBalance(u1, 0);
await dcall (u2, "support", [p3, 100]);
await checkPoor(u1, 45, true);
await dcall (u3, "support", [p3, 100]);
await checkPoor(u1, 45, true);
await dcall (u4, "support", [p3, 100]);
const ee3 = await ctcDao.events.Log.executed.next();
await mcall (testProposalContract, subCtc1.getInfo(), admin, "poke", []);
await checkPoor(u1, 45, false);
await checkPoor(u1, 65, true);
await checkGBalance(u1, 0);
await dcall (u1, "unsupport", [p3]);
await checkGBalance(u1, 100);
await dcall (u2, "unsupport", [p3]);
await dcall (u3, "unsupport", [p3]);
await dcall (u4, "unsupport", [p3]);

d("At the end of the test file.")

