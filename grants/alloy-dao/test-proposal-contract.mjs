import {loadStdlib} from '@reach-sh/stdlib';
import * as testProposalContract from './build/test-proposal-contract.main.mjs';
const stdlib = loadStdlib(process.env);

const startingBalance = stdlib.parseCurrency(10);
const adminStartingBalance = stdlib.parseCurrency(1000);
const admin = await stdlib.newTestAccount(adminStartingBalance);

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

const tokenNorm = (t) => {
  if (stdlib.connector === "ALGO") {
    return stdlib.bigNumberToNumber(t);
  } else {
    return t;
  }
}

const govTokenLaunched = await stdlib.launchToken(admin, "testGovToken", "TGT", govTokenOptions);
const govToken = tokenNorm(govTokenLaunched.id);

const debugLogging = true;
const d = (...args) => {
  if (debugLogging) {
    console.log(...args);
  }
}

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
const makePropInit = (payer, payee, netAmt, govAmt) => {
  return () => [payer, payee, netAmt, govAmt, govToken, 0, 0];
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

const checkPoor = async (user, threshold_nonparsed, shouldBePoor) => {
  // This isn't a great check.  Users need to pay transaction fees, and balances can change on Algo with rewards, so I can't just check for an expected number.
  const bal = await user.balanceOf();
  const threshold = stdlib.parseCurrency(threshold_nonparsed);
  const isPoor = stdlib.lt(bal,  threshold);
  if (shouldBePoor !== isPoor) {
    throw `user shouldBePoor (${shouldBePoor}) not matched, balance: ${bal}, threshold: ${threshold}`
  }
}

const mcall = async (ctcBackend, ctcIn, user, methodName, args) => {
  const ctc = user.contract(ctcBackend, ctcIn);
  return await ctc.apis[methodName](...args);
}

const makePropCtc = async (payer, payee, paymentAmt, govAmt) => {
  const ctcProp = admin.contract(testProposalContract);
  await startMeUp(ctcProp, makePropInit(payer, payee, paymentAmt, govAmt));
  return ctcProp;
}

const bal = async (msg, user) => {
  const convert = (x) => {
    if (stdlib.connector === "ALGO") {
      return stdlib.bigNumberToNumber(x);
    } else {
      return x;
    }
  }
  d(msg, convert(await user.balanceOf()))
}

{
  const ctc = await makePropCtc(admin.getAddress(), u1.getAddress(), stdlib.parseCurrency(20), 0);
  await bal("u1 pre", u1)
  await checkPoor(u1, 15, true);
  await mcall(testProposalContract, ctc.getInfo(), admin, "go", ["These bytes don't matter."])
  await mcall(testProposalContract, ctc.getInfo(), admin, "poke", [])
  await bal("u1 after 1st api", u1)
  await checkPoor(u1, 15, false);
  await checkPoor(u1, 25, true);
  await mcall(testProposalContract, ctc.getInfo(), admin, "go", ["pay"])
  await mcall(testProposalContract, ctc.getInfo(), admin, "poke", [])
  await bal("u1 after 2nd api", u1)
  await checkPoor(u1, 25, false);
  await checkPoor(u1, 35, true);
}

{
  const ctc = await makePropCtc(u1.getAddress(), u2.getAddress(), stdlib.parseCurrency(20), 0);

  await bal("u1 pre", u1)
  await bal("u2 pre", u2)
  await checkPoor(u2, 15, true);
  await mcall(testProposalContract, ctc.getInfo(), u1, "go", ["These bytes don't matter."])
  await mcall(testProposalContract, ctc.getInfo(), admin, "poke", [])
  await bal("u1 after 1st api", u1)
  await bal("u2 after 1st api", u2)
  await checkPoor(u2, 15, false);
  await checkPoor(u2, 25, true);
  await mcall(testProposalContract, ctc.getInfo(), u1, "go", ["NO DON'T PAY"])
  await mcall(testProposalContract, ctc.getInfo(), admin, "poke", [])
  await bal("u1 after 2nd api", u1)
  await bal("u2 after 2nd api", u2)
  await checkPoor(u2, 25, true);
}


d("At the end of the test file.")

