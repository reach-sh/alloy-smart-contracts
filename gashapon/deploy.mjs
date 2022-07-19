import { ask } from '@reach-sh/stdlib';
import * as machineBackend from './build/index.machine.mjs';
import {
  deployMachine,
  getAccFromMnemonic,
  loadRow,
  createRow,
  launchPayToken,
  createRowAccounts,
  fmtNum,
  getAccountAssets,
  stdlib,
  deployBulkCtcs,
  createNftCtcs,
} from './utils.mjs';

const MIN_ACC_BAL = 1600000;

let ctcInfo;
let payTokenId;
let rowCount;
let slotCount;
let accMachine;
let machineAddress;

const shouldCreateNewMachine = await ask.ask(
  'Do you want to create a new machine?',
  ask.yesno
);

if (!shouldCreateNewMachine) {
  const machCtcInfo = await ask.ask('Please enter the machine ctc info:');
  accMachine = await getAccFromMnemonic(
    'Please paste the mnemonic of who the machine owner:'
  );
  ctcInfo = parseInt(machCtcInfo, 10);
  const ctcMachine = accMachine.contract(machineBackend, ctcInfo);
  const { views } = ctcMachine;
  const rawRowCount = await views.numOfRows();
  const rawSlotCount = await views.numOfSlots();
  const numOfRows = fmtNum(rawRowCount[1]);
  const numOfSlots = fmtNum(rawSlotCount[1]);
  rowCount = numOfRows;
  slotCount = numOfSlots;
} else {
  console.log('OK. We will create a new machine. Please follow the promps.');
  accMachine = await getAccFromMnemonic(
    'Please paste the mnemonic of who the machine owner will be:'
  );
  const willProvidePayToken = await ask.ask(
    'Do you want to provide your own pay token:',
    ask.yesno
  );
  if (willProvidePayToken) {
    const ePayTokenId = await ask.ask('Please paste desired pay token id:');
    payTokenId = Number(ePayTokenId);
  } else {
    payTokenId = await launchPayToken(accMachine);
  }
  const ctcMachine = accMachine.contract(machineBackend);
  const {
    mCtcInfo,
    payTokenId: newPayTokId,
    numOfRows,
    numOfSlots,
    machineAddr,
  } = await deployMachine(ctcMachine, payTokenId);

  ctcInfo = parseInt(`${mCtcInfo}`, 10);
  payTokenId = newPayTokId;
  rowCount = numOfRows;
  slotCount = numOfSlots;
  machineAddress = machineAddr;
}

const accAddr = accMachine.networkAccount.addr;
const { createdAssets, assets } = await getAccountAssets(accAddr);
const createdAssetsWithBals = createdAssets.filter(ca => {
  const foundAss = assets.find(ass => ass['asset-id'] === ca.index);
  return foundAss && foundAss.amount > 0;
});
const nftIds = createdAssetsWithBals.map(ass => ass.index);
const fmtNFTIds = nftIds.map(assId => stdlib.bigNumberify(assId));

const numOfNftsToLoad = nftIds.length;
const rawRowsNeeded = numOfNftsToLoad / slotCount;
const needsAdditionalRow = rawRowsNeeded % slotCount !== 0;
let numRowsNeeded = needsAdditionalRow
  ? Math.floor(rawRowsNeeded) + 1
  : Math.floor(rawRowsNeeded);
if (numRowsNeeded > rowCount) {
  numRowsNeeded = rowCount;
  console.log('');
  console.log(
    `** Found ${numOfNftsToLoad} assets in this account. The max you can load is ${
      rowCount * slotCount
    } **`
  );
  console.log('');
}
const shouldLoad = await ask.ask(`Continue with loading?`, ask.yesno);
if (!shouldLoad) process.exit(0);

console.log('Funding row accounts...')
const rowAccs = await createRowAccounts(numRowsNeeded);
const transferAlgoPms = rowAccs.map(rowAcc =>
  stdlib.transfer(accMachine, rowAcc, MIN_ACC_BAL)
);
await Promise.all(transferAlgoPms);

const nftCtcs = createNftCtcs(accMachine, fmtNFTIds);
const deployedCtcs = await deployBulkCtcs(nftCtcs, machineAddress);

console.log('creating rows...')
const rowPms = rowAccs.map(acc => createRow(acc, ctcInfo));
await Promise.all(rowPms);

console.log('loading rows...')
const loadPms = [];
rowAccs.forEach((acc, i) => {
  setTimeout(function () {
    const itemsForRow = deployedCtcs.slice(
      i * slotCount,
      i * slotCount + slotCount
    );
    const p = loadRow(acc, itemsForRow, ctcInfo);
    loadPms.push(p);
  }, i * 250);
});
await Promise.all(loadPms);

console.log('');
console.log(`Machine Ready!`);
console.log(`Application id: ${ctcInfo}`);
console.log('')

process.exit(0);
