import {loadStdlib} from '@reach-sh/stdlib';
import * as daoContract from './build/index.main.mjs';
import * as testProposalContract from './build/test-proposal-contract.main.mjs';
const stdlib = loadStdlib(process.env);

const startingBalance = stdlib.parseCurrency(10);
const adminStartingBalance = stdlib.parseCurrency(1000);
const admin = await stdlib.newTestAccount(adminStartingBalance);
const ctcDao = admin.contract(daoContract);

const govTokenSupply = 1000;
const govTokenDecimals = 0;
const initPoolSize = 500;
const quorumSizeInit = 400;
const deadlineInit = 100;
const govTokenTotal = govTokenSupply * (Math.pow(10, govTokenDecimals));
const govTokenOptions = {
  decimals: govTokenDecimals,
  supply: govTokenSupply,
};

const govToken = await stdlib.launchToken(admin, "testGovToken", "TGT", govTokenOptions);

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
        d("The contract is ready: {ctc}")
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
const makePropInit = (payer, payee, singleAmount) => {
  return () => [payer, payee, singleAmount];
}

const makeUser = async (ngov) => {
  const u = await stdlib.newTestAccount(startingBalance);
  stdlib.transfer(admin, u, ngov, govToken);
  return u;
}

const u1 = await makeUser(100);
const u2 = await makeUser(100);
const u3 = await makeUser(100);
const u4 = await makeUser(100);
const u5 = await makeUser(100);

await startMeUp(ctcDao, dao_getInit);

const mcall = (user, methodName, args) => {
  const ctc = user.contract(daoContract, ctcDao.getInfo())
  return ctc.apis[methodName](...args);
}

const makePropCtc = async (payee, singleAmount) => {
  const ctcProp = admin.contract(testProposalContract);
  await startMeUp(ctcProp, makePropInit(await ctcDao.getContractAddress(), payee, singleAmount));
  return ctcProp;
}

// Let's give the dao some network token funds.
stdlib.transfer(admin, ctcDao.getContractAddress(), stdlib.parseCurrency(500));


mcall(u1, "propose", ["Payment", u1.getAddress(), 10, 10]);

const e1 = await ctcDao.events.Log.propose.next();
d(e1);
const p1 = e1.what[0];




console.log("Here at end of test file so far.")
// TODO - listen for events, make more accounts, make proposals, support them, etc
