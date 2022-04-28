import { loadStdlib, ask } from '@reach-sh/stdlib';
import * as machineBackend from './build/index.machine.mjs';
import * as dispenserBackend from './build/index.dispenser.mjs';

const NETWORK = 'ALGO';
const PROVIDER = 'TestNet';

const stdlib = loadStdlib(NETWORK);
stdlib.setProviderByName(PROVIDER);
const { launchToken } = stdlib;

const createNFts = async (acc, amt) => {
  const pms = Array(amt)
    .fill(null)
    .map((_, i) => launchToken(acc, `Cool NFT | edition ${i}`, `NFT${i}`));
  const res = await Promise.all(pms);
  return res.map(r => r.id);
};

const getRandomNum = (max = 100) => Math.floor(Math.random() * max);
const getRandomBigInt = () => stdlib.bigNumberify(getRandomNum());
const fmtNum = n => stdlib.bigNumberToNumber(n);
const fmtAddr = addr => stdlib.formatAddress(addr);

const askForNumber = async (msg, max) => {
  let r;
  while (!r || r > max || r <= 0) {
    const howMany = await ask.ask(msg);
    if (isNaN(howMany) || Number(howMany) > max || Number(howMany) <= 0) {
      console.log(
        '* Please enter an integer that is greater than 0 and less than 3.'
      );
    } else {
      r = Number(howMany);
    }
  }
  return r;
};

const createRow = async mCtcInfo => {
  const mnemonic = await ask.ask(
    'Please paste the mnemonic an account to own the row:'
  );
  const fmtMnemonic = mnemonic.replace(/,/g, '');
  const acc = await stdlib.newAccountFromMnemonic(fmtMnemonic);
  const ctcMachine = acc.contract(machineBackend, mCtcInfo);
  const { createRow: ctcCreateRow } = ctcMachine.a;
  const [_, numOfCreatedRows] = await ctcCreateRow();
  const fmtRn = fmtNum(numOfCreatedRows);
  console.log('Created row:', fmtRn);
};

//create NFT contract
const createNftCtcs = (acc, nftIds) =>
  nftIds.map(nftId => ({
    nftId,
    ctc: acc.contract(dispenserBackend),
  }));

const deployNftCtcs = async (nftHs, machineAddr) => {
  const ctcAddress = [];
  const deploy = nft =>
    new Promise((res, rej) => {
      nft.ctc.p.Dispenser({
        ready: ctc => {
          ctcAddress.push(ctc);
          res();
        },
        nft: nft.nftId,
        mCtcAddr: machineAddr,
      });
    });
  for (const nftCtc of nftHs) {
    await deploy(nftCtc);
  }
  return ctcAddress;
};

const loadRow_ = async (info, machineAddr) => {
  const mnemonic = await ask.ask(
    'Please paste the mnemonic of a row owner account:'
  );
  const fmtMnemonic = mnemonic.replace(/,/g, '');
  const acc = await stdlib.newAccountFromMnemonic(fmtMnemonic);
  //   const nftIds = await ask.ask(
  //     'Please paste the NFT ids you want to load as comma seperate values (i.e. 123456,456789,44444,etc.):'
  //   );
  // TODO: change this to take the NFT's from the account or pasted in NFT ID's
  // for rapid testing on testnet
  const fmtNftIds = await createNFts(acc, 3);
  const ctcMachine = acc.contract(machineBackend, info);
  const nftCtcs = createNftCtcs(acc, fmtNftIds);
  console.log('Deploying NFT contracts...');
  const nftCtcAdds = await deployNftCtcs(nftCtcs, machineAddr);
  console.log('Loading Rows...');
  for (const ctc of nftCtcAdds) {
    const [row, rIndex] = await ctcMachine.a.loadRow(ctc, getRandomBigInt());
    const fmtR = fmtNum(row);
    const fmtRi = fmtNum(rIndex);
    console.log(`Loaded slot ${fmtRi} in row ${fmtR}`);
  }
  const isRowLoaded = await ctcMachine.a.checkIfLoaded();
  return isRowLoaded;
};

// 86406489
const existingMachine = await ask.ask(
  'Do you want to load an existing machine?',
  ask.yesno
);
if (existingMachine) {
  const existingMachine = await ask.ask('Please enter the machine ctc info:');
  const fmtCtcInfo = parseInt(existingMachine, 10);
  const shouldCreateRow = await ask.ask(
    'Do you want to create a row?',
    ask.yesno
  );

  let howManyRows;
  if (shouldCreateRow) {
    const numOfRows = await askForNumber(
      'How many rows fo you want to create?',
      maxNumberOfRows
    );
    howManyRows = numOfRows;
  }
  let createdRows = 0;
  while (createdRows < howManyRows) {
    await createRow(fmtCtcInfo);
    createdRows++;
  }

  const shouldLoadRow = await ask.ask('Do you want to load a row?', ask.yesno);
  // FQWWCUXF2U4BROTZUQQECUQIXAQ4FTXI22C65PYR6T6ST5WD7C3AZDSIAU
  const machineAddress = await ask.ask(
    'Please enter the machine contract address (This will be an account address like FQWWCUXF2U4BROTZUQQE...)'
  );
  if (shouldLoadRow) {
    const isRowLoaded = await loadRow_(fmtCtcInfo, machineAddress);
    if (isRowLoaded) console.log('Row Loaded Successfully!');
    process.exit(0);
  } else {
    process.exit(0);
  }
} else {
  console.log('')
  console.log('OK. We will create a new machine. Please follow the promps.');
}

const mnemonic = await ask.ask('Please paste your mnemonic:');
const fmtMnemonic = mnemonic.replace(/,/g, '');

const accMachine = await stdlib.newAccountFromMnemonic(fmtMnemonic);
const ctcMachine = accMachine.contract(machineBackend);

const willProvidePayToken = await ask.ask(
  'Do you want to provide your own pay token?',
  ask.yesno
);
let payTokenId;
if (willProvidePayToken) {
  const ePayTokenId = await ask.ask('Please paste desired pay token id:');
  payTokenId = Number(ePayTokenId);
} else {
  // create pay token
  console.log('');
  console.log('Launching pay token...');
  const { id: nPayTokenId } = await launchToken(
    accMachine,
    'Reach Thank You',
    'RTYT'
  );
  payTokenId = fmtNum(nPayTokenId);
}
// deploy contract
let maxNumberOfRows;
let maxNumberOfRowSlots;
console.log('Deploying machine contract...');
try {
  await ctcMachine.p.Machine({
    payToken: stdlib.bigNumberify(payTokenId),
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
    maxNumberOfRows = fmtRowNum;
    maxNumberOfRowSlots = fmtSlotNum;
    console.log('');
    console.log('Number of available rows to fill:', fmtRowNum);
    console.log('Number of available slots per row:', fmtSlotNum);
    console.log('');
  } else {
    throw e;
  }
}
const mCtcInfo = await ctcMachine.getInfo();
const rawMachineAddr = await ctcMachine.getContractAddress();
const machineAddr = fmtAddr(rawMachineAddr);

console.log('');
console.log('*******************************************');
console.log('Pay token id:', payTokenId);
console.log('Machine contract info:', fmtNum(mCtcInfo));
console.log('Machine contract address:', machineAddr);
console.log('*******************************************');
console.log('');

const shouldCreateRow = await ask.ask(
  'Do you want to create a row?',
  ask.yesno
);
let howManyRows;
if (shouldCreateRow) {
  const numOfRows = await askForNumber(
    'How many rows fo you want to create?',
    maxNumberOfRows
  );
  howManyRows = numOfRows;
} else {
  process.exit(0);
}

let createdRows = 0;
while (createdRows < howManyRows) {
  await createRow(mCtcInfo);
  createdRows++;
}
const shouldLoadRow = await ask.ask('Do you want to load a row?', ask.yesno);
if (shouldLoadRow) {
  const isRowLoaded = await loadRow_(mCtcInfo, machineAddr);
  if (isRowLoaded) console.log('Row Loaded Successfully!');
} else {
}

console.log('DONE CREATING ROWS!');
