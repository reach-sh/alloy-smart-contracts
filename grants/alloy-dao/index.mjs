import {loadStdlib} from '@reach-sh/stdlib';
import * as backend from './build/index.main.mjs';
const stdlib = loadStdlib(process.env);

const startingBalance = stdlib.parseCurrency(1000);
const accAdmin = await stdlib.newTestAccount(startingBalance);
const ctc = accAdmin.contract(backend);

const govTokenSupply = 1000;
const govTokenDecimals = 0;
const govTokenTotal = govTokenSupply * (Math.pow(10, govTokenDecimals));
const govTokenOptions = {
  decimals: govTokenDecimals,
  supply: govTokenSupply,
};
const govToken = await stdlib.launchToken(accAdmin, "testGovToken", "TGT", govTokenOptions);

const initPoolSize = govTokenTotal / 10;
const quorumSizeInit = 100;
const deadlineInit = 100;

const startMeUp = async () => {
  try {
    await ctc.p.Admin({
      getInit: () => {
        return [govToken, govTokenTotal, initPoolSize, quorumSizeInit, deadlineInit];
      },
      ready: () => {
        d("The contract is ready.")
        throw 42;
      },
    });
  } catch (e) {
    if ( e !== 42) {
      throw e;
    }
  }
}

console.log("Here at end of test file so far.")
// TODO - listen for events, make more accounts, make proposals, support them, etc
