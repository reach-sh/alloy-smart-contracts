import { loadStdlib } from '@reach-sh/stdlib';
import * as vendingMachineBackend from './build/index.vendingMachine.mjs';

const AMT_TO_BUY = 40;

const stdlib = loadStdlib('ALGO');
const bal = stdlib.parseCurrency(1000);
const fmtNum = n => stdlib.bigNumberToNumber(n);
const getRandomNum = (max = 100) => Math.floor(Math.random() * max);
const getRandomBigInt = () => stdlib.bigNumberify(getRandomNum());

const userAccs = await stdlib.newTestAccounts(AMT_TO_BUY, bal);

const accMachine = await stdlib.newTestAccount(bal);
const ctcMachine = accMachine.contract(vendingMachineBackend);

let ctcInfo, packTok;

const fmtViews = async rawViews => {
  const { costOfPack, packTokSupply, howMuchPaid } = rawViews;
  const [_rawCost, rawCost] = await costOfPack();
  const [_rawPackTokSupply, rawPackTokSupply] = await packTokSupply();
  const [_howMuch, rawHowMuch] = await howMuchPaid();
  const fmtPackCost = stdlib.formatCurrency(rawCost);
  const fmtPaidAmt = stdlib.formatCurrency(rawHowMuch);
  const fmtPackTokSupply = fmtNum(rawPackTokSupply);
  return {
    packCost: fmtPackCost,
    packTokSupply: fmtPackTokSupply,
    paidAmt: fmtPaidAmt,
  };
};

const handleBuyPack = async acc => {
  const rNum = getRandomBigInt();
  const ctcUser = acc.contract(vendingMachineBackend, ctcInfo);
  const { v } = ctcUser;
  const views = await fmtViews(v);
  const { packCost, packTokSupply, paidAmt } = views;
  await acc.tokenAccept(packTok);
  const { buyPack } = ctcUser.a;
  console.log({
    cost: `${packCost} ALGO`,
    supply: packTokSupply,
    paidAmt: `${paidAmt} ALGO`,
  });
  return buyPack(rNum);
};

const handleOpenPack = async acc => {
  const rNum = getRandomBigInt();
  const ctcUser = acc.contract(vendingMachineBackend, ctcInfo);
  const { openPack } = ctcUser.a;
  const pointsFromPack = await openPack(rNum);
  const fmtPoints = fmtNum(pointsFromPack);
  console.log(`Pack contained ${fmtPoints} points!`);
};

const checkPoints = async acc => {
  const ctcUser = acc.contract(vendingMachineBackend, ctcInfo);
  const { getUser } = ctcUser.v;
  const [_rawUser, rawUserPoints] = await getUser(acc.networkAccount.addr);
  const fmtUserPoints = fmtNum(rawUserPoints);
  console.log({ points: fmtUserPoints });
};

const sendPackToSomeone = async () => {
  const sender = await stdlib.newTestAccount(bal);
  const receiver = await stdlib.newTestAccount(bal);
  await receiver.tokenAccept(packTok);
  await sender.tokenAccept(packTok);
  await handleBuyPack(sender)
  await stdlib.transfer(sender, receiver, 1, packTok);
  console.log('Pack sent to another user!')
  await handleOpenPack(receiver)
  console.log('New owner opened pack!!')
};

// deploy contract
await stdlib.withDisconnect(() =>
  ctcMachine.p.Deployer({ ready: stdlib.disconnect })
);
const { packTok: pTokV } = ctcMachine.v;
const [_rawPackTok, rawPackTok] = await pTokV();
packTok = fmtNum(rawPackTok);
ctcInfo = await ctcMachine.getInfo();
console.log('Contract Deployed!');

for (const acc of userAccs) {
  await handleBuyPack(acc);
  await handleOpenPack(acc);
  await checkPoints(acc);
}

await sendPackToSomeone();

