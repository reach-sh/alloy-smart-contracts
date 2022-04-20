import { loadStdlib } from '@reach-sh/stdlib';
import * as machineBackend from '../build/index.machine.mjs';
import * as dispenserBackend from '../build/index.dispenser.mjs';
import { bal, fmtAddr } from './index.mjs';

const stdlib = loadStdlib('ALGO-devnet');
const { launchToken } = stdlib;

const chkScenerio__ = async (lab, go, opts = {}) => {
  const accMachine = await stdlib.newTestAccount(bal);
  const ctcMachine = accMachine.contract(machineBackend);

  // create pay token
  const { id: payTokenId } = await launchToken(
    accMachine,
    'Reach Thank You',
    'RTYT'
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
      console.log('Deployed');
    } else {
      throw e;
    }
  }
  const rawMachineAddr = await ctcMachine.getContractAddress();
  const machineAddr = fmtAddr(rawMachineAddr);
  const mCtcInfo = await ctcMachine.getInfo();
  const x = { machineAddr, mCtcInfo };
  await go(chk, x, chkErr);
};

export const chkScenario = async (lab_in, go, opts = {}) => {
  jobs.push(() => chkScenerio__(lab_in, go, opts));
};

const loud = true;
const cases = [];
let tests = 0;
let fails = 0;
export const chk = (id, actual, expected, xtra = {}) => {
  tests++;
  const xtras = JSON.stringify(xtra, null, 2);
  const exps = JSON.stringify(expected, null, 2);
  let acts = JSON.stringify(actual, null, 2);
  if (acts === '{}') {
    acts = actual.toString();
  }
  let show;
  let err;
  if (exps !== acts) {
    fails++;
    err = `${xtras}\nexpected ${exps}, got ${acts}`;
    show = 'FAIL';
  } else if (loud) {
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
export const chkErr = async (id, exp, f, xtra = {}) => {
  const clean = s => s.replace(/\0/g, '').replace(/\\u0000/g, '');
  const exps = clean(exp);
  try {
    const r = await f();
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
    es = clean(es);
    chk(id, es.includes(exps), true, { ...xtra, e, es, exps });
  }
};

// Parallelization system
const howManyAtOnce = 15;
const jobs = [];
export const sync = async () => {
  console.log(`${jobs.length} jobs scheduled, running...`);
  while (jobs.length > 0) {
    console.log(`Spawning ${howManyAtOnce} of ${jobs.length} jobs`);
    const active = [];
    while (jobs.length > 0 && active.length < howManyAtOnce) {
      active.push(jobs.pop()());
    }
    console.log(`Waiting for ${active.length} jobs`);
    await Promise.all(active);
  }
  console.log('All jobs done');
};
