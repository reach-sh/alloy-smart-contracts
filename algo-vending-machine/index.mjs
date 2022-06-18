import { loadStdlib } from '@reach-sh/stdlib';
import * as vendingMachineBackend from './build/index.vendingMachine.mjs';

const AMT_TO_BUY = 5;

const stdlib = loadStdlib('ALGO');
const bal = stdlib.parseCurrency(1000);
const fmtNum = n => stdlib.bigNumberToNumber(n);
const getRandomNum = (max = 100) => Math.floor(Math.random() * max);
const getRandomBigInt = () => stdlib.bigNumberify(getRandomNum());

const createNFT = async acc =>
  await stdlib.launchToken(acc, `Lightning Zeus (season one)`, `ZEUS`, {
    decimals: 0,
  });

const userAccs = await stdlib.newTestAccounts(AMT_TO_BUY, bal);

const accDeployer = await stdlib.newTestAccount(bal);
const ctcMachine = accDeployer.contract(vendingMachineBackend);

let ctcInfo, packTok, NFT;

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
    currentCost: `${packCost} ALGO`,
    currentSupply: packTokSupply,
    contractBalance: `${paidAmt} ALGO`,
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

const transferPack = async () => {
  const sender = await stdlib.newTestAccount(bal);
  const receiver = await stdlib.newTestAccount(bal);
  await receiver.tokenAccept(packTok);
  await sender.tokenAccept(packTok);
  await handleBuyPack(sender);
  await stdlib.transfer(sender, receiver, 1, packTok);
  await handleOpenPack(receiver);
  console.log('Pack transfered!');
  checkPoints(receiver);
};

const handleLoad = async () => {
  const rNum = getRandomBigInt();
  const ctcUser = accDeployer.contract(vendingMachineBackend, ctcInfo);
  const { load } = ctcUser.a;
  await load(rNum, 1000);
  console.log('Laoded!');
};

const handleCrank = async acc => {
  const rNum = getRandomBigInt();
  const ctcUser = acc.contract(vendingMachineBackend, ctcInfo);
  const { crank } = ctcUser.a;
  const nftReceived = await crank(rNum);
  const fmtNFT = fmtNum(nftReceived);
  console.log(`NFT Received: ${fmtNFT}`);
};

const { id: nftId } = await createNFT(accDeployer);

// deploy contract
await stdlib.withDisconnect(() =>
  ctcMachine.p.Deployer({
    ready: stdlib.disconnect,
    NFT: nftId,
  })
);
// set global views for all functions to use
const { packTok: pTokV, NFT: nftV } = ctcMachine.v;
const [_rawPackTok, rawPackTok] = await pTokV();
const [_rawNFT, rawNFT] = await nftV();
ctcInfo = await ctcMachine.getInfo();
NFT = await fmtNum(rawNFT);
packTok = fmtNum(rawPackTok);

await handleLoad();

for (const acc of userAccs) {
  await handleBuyPack(acc);
  await handleOpenPack(acc);
  await checkPoints(acc);
  await handleCrank(acc);
}

await transferPack();