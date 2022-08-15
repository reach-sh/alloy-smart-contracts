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
  return () => [payer, payee, netAmt, govAmt, govToken];
}


const makeUser = async (ngov) => {
  const u = await stdlib.newTestAccount(startingBalance);
  await u.tokenAccept(govToken);
  await stdlib.transfer(admin, u, ngov, govToken);
  return u;
}

const u1 = await makeUser(100);
const u2 = await makeUser(100);
const u3 = await makeUser(100);
const u4 = await makeUser(100);
const u5 = await makeUser(100);

await startMeUp(ctcDao, dao_getInit);

const mcall = async (user, methodName, args) => {
  const ctc = user.contract(daoContract, ctcDao.getInfo())
  return await ctc.apis[methodName](...args);
}

const makePropCtc = async (payee, paymentAmt, govAmt) => {
  const ctcProp = admin.contract(testProposalContract);
  await startMeUp(ctcProp, makePropInit(await ctcDao.getContractAddress(), payee, paymentAmt, govAmt));
  return ctcProp;
}

// Let's give the dao some network token funds.
await mcall(admin, "fund", [stdlib.parseCurrency(500), 0]);



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

await mcall(u1, "propose", [["Payment", [u1.getAddress(), stdlib.parseCurrency(10), 10]]]);

await checkPoor(u1, 15, true);
await checkGBalance(u1, 100);

const pe1 = await ctcDao.events.Log.propose.next();
const p1 = pe1.what[0];

await mcall (u1, "support", [p1, 100]);
await checkPoor(u1, 15, true);
await checkGBalance(u1, 0);
await mcall (u1, "unsupport", [p1]);
await checkPoor(u1, 15, true);
await checkGBalance(u1, 100);
await mcall (u1, "support", [p1, 100]);
await checkPoor(u1, 15, true);
await checkGBalance(u1, 0);
await mcall (u2, "support", [p1, 100]);
await checkPoor(u1, 15, true);
await mcall (u3, "support", [p1, 100]);
await checkPoor(u1, 15, true);
await mcall (u4, "support", [p1, 100]);
const ee1 = await ctcDao.events.Log.executed.next();
await checkPoor(u1, 15, false);
await checkGBalance(u1, 10);
await mcall (u1, "unsupport", [p1]);
await checkGBalance(u1, 110);
await mcall (u2, "unsupport", [p1]);
await mcall (u3, "unsupport", [p1]);
await mcall (u4, "unsupport", [p1]);

await mcall(u1, "unpropose", [p1]);
await mcall(u1, "fund", [stdlib.parseCurrency(10), 10]);




// Test CallContract action

const paymentAmt = stdlib.parseCurrency(40);
const subGovAmt = 0;
const subCtc1 = await makePropCtc(await u1.getAddress(), paymentAmt, subGovAmt);


await mcall(u1, "propose", [["CallContract", [await subCtc1.getInfo(), paymentAmt, subGovAmt, "These bytes really don't matter."]]]);

const pe2 = await ctcDao.events.Log.propose.next();
const p2 = pe2.what[0];

await mcall (u1, "support", [p2, 100]);
await checkPoor(u1, 25, true);
await checkGBalance(u1, 0);
await mcall (u2, "support", [p2, 100]);
await checkPoor(u1, 25, true);
await mcall (u3, "support", [p2, 100]);
await checkPoor(u1, 25, true);
d("\nHERE just before vote wins ===---===---===---===---===---===---\n")
d("subCtc1.getInfo", await subCtc1.getInfo())
d("u1:", await u1.getAddress())
// TODO -- Unless I comment out the transfer, this errors with wrong address.  Particularly interesting here is that if I decode the Address that it says is wrong, it matches the address for u1 but with every other byte swapped.  I have no idea how that swapping could be occurring.
await mcall (u4, "support", [p2, 100]);
const ee2 = await ctcDao.events.Log.executed.next();
//await checkPoor(u1, 25, false);
//await checkPoor(u1, 45, true);
//await checkGBalance(u1, 0);
await mcall (u1, "unsupport", [p2]);
//await checkGBalance(u1, 100);
await mcall (u2, "unsupport", [p2]);
await mcall (u3, "unsupport", [p2]);
await mcall (u4, "unsupport", [p2]);

d("\nHERE after first half ===---===---===---===---===---===---\n")

// Get the second half of funding from the test contract.
//await mcall(u5, "propose", [["CallContract", [await subCtc1.getInfo(), stdlib.parseCurrency(0), 0, "NO PAY"]]]);
await mcall(u5, "propose", [["CallContract", [await subCtc1.getInfo(), stdlib.parseCurrency(0), 0, "pay"]]]);

const pe3 = await ctcDao.events.Log.propose.next();
const p3 = pe3.what[0];

await mcall (u1, "support", [p3, 100]);
//await checkPoor(u1, 45, true);
//await checkGBalance(u1, 0);
await mcall (u2, "support", [p3, 100]);
//await checkPoor(u1, 45, true);
await mcall (u3, "support", [p3, 100]);
//await checkPoor(u1, 45, true);
d("\nHERE just before supporting 2nd CallContract proposal ===---===---===---===---===---===---\n")
// TODO - I get the same “invalid Account reference” error here if I call with pay (if I've commented out the earlier transfer).
// TODO - if I comment out the transfer of the first API call and give a no-pay argument for the second, I get an error: logic eval error: fee too small
// TODO - if I comment out all transfers in the called contract, I still get an error on the second call with an assert about GroupSize.  I'm not sure what that is.
await mcall (u4, "support", [p3, 100]);
const ee3 = await ctcDao.events.Log.executed.next();
//await checkPoor(u1, 45, false);
//await checkPoor(u1, 65, true);
//await checkGBalance(u1, 0);
//await mcall (u1, "unsupport", [p3]);
//await checkGBalance(u1, 100);
//await mcall (u2, "unsupport", [p3]);
//await mcall (u3, "unsupport", [p3]);
//await mcall (u4, "unsupport", [p3]);

d("\nHERE ===---===---===---===---===---===---\n")

d("At the end of the test file.")

