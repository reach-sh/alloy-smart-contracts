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

const startingBalance = 10;
const adminStartingBalance = stdlib.parseCurrency(1000);
const admin = await stdlib.newTestAccount(adminStartingBalance);
const ctcDao = await admin.contract(daoContract);

const govTokenSupply = 1000;
const govTokenDecimals = 0;
const initPoolSize = 500;
const quorumSizeInit = 50_001;
const deadlineInit = 1000;
const govStartBalance = 100;
const govTokenTotal = govTokenSupply * (Math.pow(10, govTokenDecimals));
const govTokenOptions = {
  decimals: govTokenDecimals,
  supply: govTokenSupply,
};

const govTokenLaunched = await stdlib.launchToken(admin, "testGovToken", "TGT", govTokenOptions);
const govToken = govTokenLaunched.id;


const hl = (color) => {
  if (color == "red") {
    return "\x1b[31m";
  } else if (color == "green") {
    return "\x1b[32m";
  } else if (color == "cyan") {
    return "\x1b[36m";
  } else {
    return "\x1b[0m";
  }
}

const mcall = async (ctcBackend, ctcIn, user, methodName, args) => {
  d(`Calling method: ${hl("cyan")}${await methodName}${hl("off")}`);
  d(`   - User: ${await (await user).getAddress()}`);
  d(`   - contract: ${await ctcIn}`);
  d(`   - Args: ${JSON.stringify(await args)}`);
  d(``);
  const ctc = user.contract(ctcBackend, ctcIn);
  return await ctc.apis[methodName](...args);
}

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
const dBalance = async (user) => {
  d(`Balance for ${await user.getAddress()}: gov: ${await user.balanceOf(govToken)}, net: ${stdlib.formatCurrency(await user.balanceOf())}`)
}

const noExpected = "Expected error, got none";
const expect = async (goFunc, message) => {
  try {
    d("Doing something fishy...")
    await goFunc()
    throw noExpected;
  } catch (e) {
    // TODO - this would be better if we searched the raised exception for the text of the assertion we expect to fail.
    if (e === noExpected) {
      throw noExpected + " for: " + message;
    }
    d(`Caught expected exception for test: ${message}.\n`);
  }
}

const startMeUp = async (ctc, getInit, ctcName) => {
  try {
    await ctc.p.Admin({
      getInit: getInit,
      ready: async () => {
        d(`${ctcName} is ready as: ${await ctc.getInfo()}.`);
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
  const u = await stdlib.newTestAccount(stdlib.parseCurrency(startingBalance));
  await u.tokenAccept(govToken);
  await stdlib.transfer(admin, u, ngov, govToken);
  if (stdlib.connector !== "ALGO") {
    u.setGasLimit(5000000);
  }
  return u;
}

const u1 = await makeUser(govStartBalance);
const u2 = await makeUser(govStartBalance);
const u3 = await makeUser(govStartBalance);
const u4 = await makeUser(govStartBalance);
const u5 = await makeUser(govStartBalance);

const userWithNoGovTokens = await makeUser(0);

// Baseline numbers of assets for testing
// During tests users will spend network tokens on contract calls, but no more than half their starting balance.
const nb = startingBalance / 2;

await startMeUp(ctcDao, dao_getInit, "Dao contract");

const dcall = async (user, methodName, args) => {
  return await mcall(daoContract, ctcDao.getInfo(), user, methodName, args);
}

const makePropCtc = async (payee, paymentAmt, govAmt) => {
  const ctcProp = admin.contract(testProposalContract);
  await startMeUp(ctcProp, makePropInit(await ctcDao.getContractAddress(), payee, paymentAmt, govAmt), `Test helper contract (payee: ${payee})`);
  return ctcProp;
}


//////////////////// Start testing proper ////////////////////


// Let's give the dao some network token funds.
await dcall(admin, "fund", [stdlib.parseCurrency(500), 0]);

// Make a proposal that won't be passed or removed, just to test that there can be more than one at a time...
await dcall(userWithNoGovTokens, "propose", [["Payment", [await admin.getAddress(), stdlib.parseCurrency(10), 10]], "unpopular proposal"]);
const p_leaveAlone = (await ctcDao.events.Log.propose.next()).what[0];



{
  d("\n\n=== Test Payment Action ===\n\n")

  await dcall(u1, "propose", [["Payment", [u1.getAddress(), stdlib.parseCurrency(10), 10]], "proposal message"]);

  await checkPoor(u1, nb + 10, true);
  await checkGBalance(u1, govStartBalance);

  const pe1 = await ctcDao.events.Log.propose.next();
  const p1 = pe1.what[0];

  await dcall (u1, "support", [p1, govStartBalance]);
  await checkPoor(u1, nb + 10, true);
  await checkGBalance(u1, 0);
  await dcall (u1, "unsupport", [p1]);
  await checkPoor(u1, nb + 10, true);
  await checkGBalance(u1, govStartBalance);
  await dcall (u1, "support", [p1, govStartBalance]);
  await checkPoor(u1, nb + 10, true);
  await checkGBalance(u1, 0);
  await dcall (u2, "support", [p1, govStartBalance]);
  await checkPoor(u1, nb + 10, true);
  d("About to cast final supporting vote...")
  await dBalance(u1);
  await dcall (u3, "support", [p1, govStartBalance]);
  const ee1 = await ctcDao.events.Log.executed.next();
  await checkPoor(u1, nb + 10, false);
  await checkGBalance(u1, 10);
  d("Payment proposal supported.")
  await dBalance(u1);
  d("Users can now clean up their support/propose calls.")
  await dcall (u1, "unsupport", [p1]);
  await checkGBalance(u1, govStartBalance + 10);
  await dcall(u1, "unpropose", [p1]);
  await dcall (u2, "unsupport", [p1]);
  await dcall (u3, "unsupport", [p1]);


  d("")
  d("Let's reset that payment call by having the recipient re-fund the DAO.")
  await dcall(u1, "fund", [stdlib.parseCurrency(10), 10]);
}



const testCallContract = async (paySecond) => {
  d("\n\n=== Test Call Contract Action ===\n\n")

  const paymentAmt = stdlib.parseCurrency(40);
  const subGovAmt = 10;
  const subCtc1 = await makePropCtc(await u1.getAddress(), paymentAmt, subGovAmt);


  await dcall(u5, "propose", [["CallContract", [await subCtc1.getInfo(), paymentAmt, subGovAmt, "These bytes really don't matter."]], "proposal message"]);

  const pe2 = await ctcDao.events.Log.propose.next();
  const p2 = pe2.what[0];

  await dcall (u1, "support", [p2, govStartBalance]);
  await checkPoor(u1, nb + 20, true);
  await checkGBalance(u1, 0);
  await dcall (u2, "support", [p2, govStartBalance]);
  await checkPoor(u1, nb + 20, true);
  d("About to cast final supporting vote...");
  dBalance(u1);
  await dcall (u3, "support", [p2, govStartBalance]);
  const ee2 = await ctcDao.events.Log.executed.next();
  await mcall (testProposalContract, subCtc1.getInfo(), admin, "poke", []);
  await checkPoor(u1, nb + 20, false);
  await checkPoor(u1, nb + 40, true);
  await checkGBalance(u1, subGovAmt / 2);
  d("CallContract proposal supported...")
  dBalance(u1);
  await dcall (u1, "unsupport", [p2]);
  await checkGBalance(u1, govStartBalance + (subGovAmt / 2));
  await dcall (u2, "unsupport", [p2]);
  await dcall (u3, "unsupport", [p2]);
  await dcall(u5, "unpropose", [p2]);


  // Get the second half of funding from the test contract.
  d("Proposing second round of CallContract for the external test contract.")
  d(`Proposal pays second round: ${paySecond}`)
  const payString = paySecond ? "pay" : "NO PAY";
  await dcall(u5, "propose", [["CallContract", [await subCtc1.getInfo(), stdlib.parseCurrency(0), 0, payString]], "proposal message"]);
  const pe3 = await ctcDao.events.Log.propose.next();
  const p3 = pe3.what[0];

  await dcall (u1, "support", [p3, govStartBalance]);
  await checkPoor(u1, nb + 40, true);
  await checkGBalance(u1, subGovAmt / 2);
  await dcall (u2, "support", [p3, govStartBalance]);
  await checkPoor(u1, nb + 40, true);
  await dcall (u3, "support", [p3, govStartBalance]);
  const ee3 = await ctcDao.events.Log.executed.next();
  await mcall (testProposalContract, subCtc1.getInfo(), admin, "poke", []);
  dBalance(u1);
  if (paySecond) {
    await checkPoor(u1, nb + 40, false);
    await checkPoor(u1, nb + 60, true);
    await checkGBalance(u1, subGovAmt);
    d("Re-funding to set baseline for later tests...")
    await dcall(u1, "fund", [paymentAmt, subGovAmt]);
  } else {
    await checkPoor(u1, nb + 20, false);
    await checkPoor(u1, nb + 40, true);
    await checkGBalance(u1, subGovAmt / 2);
    d("Re-funding to set baseline for later tests...")
    await dcall(u1, "fund", [paymentAmt / 2, subGovAmt / 2]);
  }
  await dcall(u5, "unpropose", [p3]);
  await dcall (u1, "unsupport", [p3]);
  await checkGBalance(u1, govStartBalance);
  await dcall (u2, "unsupport", [p3]);
  await dcall (u3, "unsupport", [p3]);
}
await testCallContract(true);
await testCallContract(false);


{
  d("\n\n=== Test Changing Quorum ===\n\n");
  d("Change quorum size to 0.1%");
  await dcall(u1, "propose", [["ChangeParams", [100, deadlineInit]], "Let practically anyone pass proposals!"]);
  const p1 = (await ctcDao.events.Log.propose.next()).what[0];
  await dcall (u1, "support", [p1, govStartBalance]);
  await dcall (u2, "support", [p1, govStartBalance]);
  await dcall (u3, "support", [p1, govStartBalance]);
  const ee1 = await ctcDao.events.Log.executed.next();
  d("Quorum size change done!");
  await dcall (u1, "unsupport", [p1]);
  await dcall (u1, "unpropose", [p1]);
  await dcall (u2, "unsupport", [p1]);
  await dcall (u3, "unsupport", [p1]);
  d("Change quorum size to 0.01%");
  await dcall(u1, "propose", [["ChangeParams", [10, deadlineInit]], "Go nuts!"]);
  const p2 = (await ctcDao.events.Log.propose.next()).what[0];
  await dcall (u1, "support", [p2, govStartBalance]);
  const ee2 = await ctcDao.events.Log.executed.next();
  d("Quorum size change done!");
  await dcall (u1, "unsupport", [p2]);
  await dcall (u1, "unpropose", [p2]);
}


{
  d("\n\n=== Test That Bad Behaviors Don't Work ===\n\n")

  await dcall(u1, "propose", [["Payment", [u1.getAddress(), stdlib.parseCurrency(10), 10]], "proposal message"]);
  const p1 = (await ctcDao.events.Log.propose.next()).what[0];
  await expect(async () => await dcall(u1, "propose", [["Payment", [u1.getAddress(), stdlib.parseCurrency(10), 10]], "proposal message"]), "Can't make a second proposal.");
  await expect(async () => await dcall(u2, "unpropose", [p1]), "Can't unpropose for someone else");
  await dcall(u1, "unpropose", [p1]);
  await expect(async () => await dcall(u2, "support", [p1, govStartBalance]), "Can't support unproposed proposals")

  const tooMuchMoneyNet = stdlib.parseCurrency(1_000_000_000);
  const tooMuchMoneyGov = govTokenSupply;
  const subCtcNet = await makePropCtc(await u1.getAddress(), tooMuchMoneyNet, 0);
  const subCtcGov = await makePropCtc(await u1.getAddress(), 0, tooMuchMoneyGov);
  const tooMuchMoneyProp = async (payOrCall, govOrNet) => {
    const callArgs = payOrCall ? [] : ["a string"];
    const contractAddr = 0;
    const method = payOrCall ? "Payment" : "CallContract";
    const addr = payOrCall ? await u1.getAddress() :
          govOrNet ? await subCtcGov.getInfo() : await subCtcNet.getInfo();
    const govAmt = govOrNet ? tooMuchMoneyGov : 0;
    const netAmt = govOrNet ? 0 : tooMuchMoneyNet;
    await dcall(u1, "propose", [[method, [addr, netAmt, govAmt, ...callArgs]], "msg"]);
    const pb = (await ctcDao.events.Log.propose.next()).what[0];
    await expect(async () => await dcall (u1, "support", [pb, govStartBalance]), `Can't pass final support for ${payOrCall ? "pay" : "call"} when there aren't enough ${govOrNet ? "government" : "network"} tokens to pay.`);
    await dcall(u1, "unpropose", [pb]);
  }
  await tooMuchMoneyProp(false, false);
  await tooMuchMoneyProp(false, true);
  await tooMuchMoneyProp(true, false);
  await tooMuchMoneyProp(true, true);


  // Change quorum back to original levels.
  await dcall(u1, "propose", [["ChangeParams", [quorumSizeInit, deadlineInit]], "Return to normal params"]);
  const pq = (await ctcDao.events.Log.propose.next()).what[0];
  await dcall (u1, "support", [pq, govStartBalance]);
  const eeq = await ctcDao.events.Log.executed.next();
  await dcall (u1, "unsupport", [pq]);

  await expect(async () => await dcall (u1, "support", [pq, govStartBalance]), "Can't support an already executed proposal.");
  await dcall (u1, "unpropose", [pq]);

  await dcall(u1, "propose", [["ChangeParams", [10, deadlineInit]], "Go nuts!"]);
  const pq2 = (await ctcDao.events.Log.propose.next()).what[0];
  await dcall (u1, "support", [pq2, govStartBalance/2]);
  await expect(async () => await dcall (u1, "support", [pq2, govStartBalance/2]), "Can't support a proposal twice, need to unsupport first.");

  await dcall(u2, "propose", [["ChangeParams", [10, deadlineInit]], "Go nuts!"]);
  const pq3 = (await ctcDao.events.Log.propose.next()).what[0];
  await expect(async () => await dcall (u1, "support", [pq3, govStartBalance/2]), "Can't support two proposals at the same time.");


  await dcall (u1, "unsupport", [pq2]);
  await dcall (u1, "unpropose", [pq2]);
  await dcall (u2, "unpropose", [pq3]);

}

d("At the end of the test file.")

