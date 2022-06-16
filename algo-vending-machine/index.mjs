import { loadStdlib } from '@reach-sh/stdlib';
import * as vendingMachineBackend from './build/index.vendingMachine.mjs';

const AMT_TO_BUY = 50;

const stdlib = loadStdlib('ALGO');
const bal = stdlib.parseCurrency(1000);
const fmtNum = n => stdlib.bigNumberToNumber(n);
const bigNumberify = n => stdlib.bigNumberify(n);

const userAccs = await stdlib.newTestAccounts(AMT_TO_BUY, bal);

const accMachine = await stdlib.newTestAccount(bal);
const ctcMachine = accMachine.contract(vendingMachineBackend);

const fmtViews = async rawViews => {
  const { costOfPack, packTok, packTokSupply } = rawViews;
  const [_rawCost, rawCost] = await costOfPack();
  const [_rawPackTok, rawPackTok] = await packTok();
  const [_rawPackTokSupply, rawPackTokSupply] = await packTokSupply();
  const fmtPackCost = fmtNum(rawCost);
  const fmtPackTok = fmtNum(rawPackTok);
  const fmtPackTokSupply = fmtNum(rawPackTokSupply);
  return {
    packCost: fmtPackCost,
    packTok: fmtPackTok,
    packTokSupply: fmtPackTokSupply,
  };
};

const getPackForAcc = async (acc, ctcInfo) => {
  await acc.tokenAccept(bigNumberify(packTok));
  const ctcUser = acc.contract(vendingMachineBackend, ctcInfo);
  const { v } = ctcUser;
  const { getPack } = ctcUser.a;
  const views = await fmtViews(v);
  const { packCost, packTokSupply } = views;
  console.log({
    cost: packCost,
    supply: packTokSupply,
  });
  return getPack();
};

let apis;
let ctcViews;
// deploy contract
try {
  await ctcMachine.p.Deployer({
    ready: x => {
      throw { x };
    },
  });
  throw new Error('impossible');
} catch (e) {
  if ('x' in e) {
    console.log('Deployed!');
    const { a, v } = ctcMachine;
    ctcViews = await fmtViews(v);
    apis = a;
  } else {
    throw e;
  }
}

const { packTok } = ctcViews;
const ctcInfo = await ctcMachine.getInfo();

for (const acc of userAccs) {
  await getPackForAcc(acc, ctcInfo);
}
