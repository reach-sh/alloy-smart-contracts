import { loadStdlib } from '@reach-sh/stdlib';
import * as machineBackend from './build/index.machine.mjs';
import { bal, fmtAddr, fmtNum } from './index.mjs';

const stdlib = loadStdlib('ALGO-devnet');
const { launchToken } = stdlib;

const LOUD = true;
const HOW_MANY_AT_ONCE = 15;

const jobs = [];
const cases = [];
const failedTests = [];

let tests = 0;

const chkScenerio__ = async (lab, go, opts = {}) => {
  const accMachine = await stdlib.newTestAccount(bal);
  const ctcMachine = accMachine.contract(machineBackend);

  let v;

  // create pay token
  const { id: payTokenId } = await launchToken(
    accMachine,
    'Reach Thank You',
    'RTYT',
    { decimals: 0 }
  );
  // deploy contract
  try {
    await ctcMachine.p.Machine({
      payToken: payTokenId,
      ready: x => {
        throw { x };
      },
    });
    throw new Error('impossible');
  } catch (e) {
    if ('x' in e) {
      const { v: views } = ctcMachine;
      const { numOfRows, numOfSlots } = views;
      const [rawRowNum, rawSlotNum] = await Promise.all([
        numOfRows(),
        numOfSlots(),
      ]);
      const fmtRowNum = fmtNum(rawRowNum[1]);
      const fmtSlotNum = fmtNum(rawSlotNum[1]);
      v = { rows: fmtRowNum, slots: fmtSlotNum, ...views };
    } else {
      throw e;
    }
  }
  const rawMachineAddr = await ctcMachine.getContractAddress();
  const machineAddr = fmtAddr(rawMachineAddr);
  const mCtcInfo = await ctcMachine.getInfo();
  const x = { machineAddr, mCtcInfo, payTokenId, accMachine, v };
  const asserts = { equals: chk, error: chkErr, isTrue };
  await go(asserts, x, lab);
};

export const describe = async (lab_in, go, opts = {}) => {
  tests++;
  jobs.push(() => chkScenerio__(lab_in, go, opts));
};

export const isTrue = (id, assertion) => {
  if (assertion && LOUD) {
    console.log('SUCC', { id, assertion });
  } else {
    failedTests.push(id);
  }
};

export const chk = (id, actual, expected, xtra = {}) => {
  const xtras = JSON.stringify(xtra, null, 2);
  const exps = JSON.stringify(expected, null, 2);
  let acts = JSON.stringify(actual, null, 2);
  if (acts === '{}') {
    acts = actual.toString();
  }
  let show;
  let err;
  if (exps !== acts) {
    failedTests.push(id);
    err = `${xtras}\nexpected ${exps}, got ${acts}`;
    show = 'FAIL';
  } else if (LOUD) {
    show = 'SUCC';
  }
  cases.push({ id, time: xtra.time, err });
  if (show) {
    if (expected?._isBigNumber) {
      expected = expected.toString();
    }
    if (actual?._isBigNumber) {
      actual = actual.toString();
    }
    console.log(show, { ...xtra, id, expected, actual });
  }
};

// Unit tests
export const chkErr = async (id, f) => {
  try {
    const r = await f();
    failedTests.push(id);
    throw Error(`Expected error, but got ${JSON.stringify(r)}`);
  } catch (e) {
    let es = e.toString();
    if (es === '[object Object]') {
      try {
        es = JSON.stringify(e);
      } catch (e) {
        void e;
      }
    }
  }
};

// Parallelization system
export const startTests = async () => {
  console.log(`${jobs.length} jobs scheduled, running...`);
  while (jobs.length > 0) {
    console.log(`Spawning ${HOW_MANY_AT_ONCE} of ${jobs.length} jobs`);
    const active = [];
    while (jobs.length > 0 && active.length < HOW_MANY_AT_ONCE) {
      active.push(jobs.pop()());
    }
    console.log(`Waiting for ${active.length} jobs`);
    await Promise.all(active);
  }
  if (failedTests.length === 0) {
    console.log('');
    console.log(`✅ ${tests} out of ${tests} tests passed!✅`);
    console.log('');
  } else {
    console.log('');
    console.log(`❌ ${failedTests.length} out of ${tests} tests failed ❌`);
    console.log(failedTests);
    console.log('');
  }
  process.exit(0);
};
