import { loadStdlib } from '@reach-sh/stdlib';
import * as vendingMachineBackend from './build/index.vendingMachine.mjs';

const AMT_TO_BUY = 51;

const stdlib = loadStdlib('ALGO');
const bal = stdlib.parseCurrency(1000);
const fmtNum = n => stdlib.bigNumberToNumber(n);
const bigNumberify = n => stdlib.bigNumberify(n);
const getRandomNum = (max = 100) => Math.floor(Math.random() * max);
const getRandomBigInt = () => stdlib.bigNumberify(getRandomNum());

const userAccs = await stdlib.newTestAccounts(AMT_TO_BUY, bal);

const accMachine = await stdlib.newTestAccount(bal);
const ctcMachine = accMachine.contract(vendingMachineBackend);

const fmtViews = async rawViews => {
  const { costOfPack, packTok, packTokSupply, howMuchPaid, getUser } = rawViews;
  const [_rawCost, rawCost] = await costOfPack();
  const [_rawPackTok, rawPackTok] = await packTok();
  const [_rawPackTokSupply, rawPackTokSupply] = await packTokSupply();
  const [_howMuch, rawHowMuch] = await howMuchPaid();
  const fmtPackCost = stdlib.formatCurrency(rawCost);
  const fmtPaidAmt = stdlib.formatCurrency(rawHowMuch);
  const fmtPackTok = fmtNum(rawPackTok);
  const fmtPackTokSupply = fmtNum(rawPackTokSupply);
  return {
    packCost: fmtPackCost,
    packTok: fmtPackTok,
    packTokSupply: fmtPackTokSupply,
    paidAmt: fmtPaidAmt,
  };
};

const getPack = async (acc, ctcInfo) => {
  const rNum = getRandomBigInt();
  const ctcUser = acc.contract(vendingMachineBackend, ctcInfo);
  const { v } = ctcUser;
  const views = await fmtViews(v);
  const { packCost, packTokSupply, packTok, paidAmt } = views;
  await acc.tokenAccept(bigNumberify(packTok));
  const { getPack } = ctcUser.a;
  console.log({
    cost: `${packCost} ALGO`,
    supply: packTokSupply,
    paidAmt: `${paidAmt} ALGO`,
  });
  return getPack(rNum);
};

const openPack = async (acc, ctcInfo) => {
  const rNum = getRandomBigInt();
  const ctcUser = acc.contract(vendingMachineBackend, ctcInfo);
  const { openPack } = ctcUser.a;
  const pointsFromPack = await openPack(rNum);
  const fmtPoints = fmtNum(pointsFromPack);
  console.log(`Pack contained ${fmtPoints} points!`);
};

const checkPoints = async (acc, ctcInfo) => {
  const ctcUser = acc.contract(vendingMachineBackend, ctcInfo);
  const { getUser } = ctcUser.v;
  const [_rawUser, rawUserPoints] = await getUser(acc.networkAccount.addr);
  const fmtUserPoints = fmtNum(rawUserPoints)
  console.log({ points: fmtUserPoints });
};

// deploy contract
await stdlib.withDisconnect(() =>
  ctcMachine.p.Deployer({ ready: stdlib.disconnect })
);
console.log('Contract Deployed!');

const ctcInfo = await ctcMachine.getInfo();

for (const acc of userAccs) {
  await getPack(acc, ctcInfo);
}

for (const acc of userAccs) {
  await openPack(acc, ctcInfo);
}

for (const acc of userAccs) {
  await checkPoints(acc, ctcInfo);
}
