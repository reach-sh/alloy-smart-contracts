import { ask } from '@reach-sh/stdlib';
import * as machineBackend from './build/index.machine.mjs';
import {
  deployMachine,
  getAccFromMnemonic,
  askForNumber,
  loadRow,
  createRow,
  launchPayToken,
} from './utils.mjs';

let ctcInfo;
let payTokenId;

const existingMachine = await ask.ask(
  'Do you want to load an existing machine?',
  ask.yesno
);

if (existingMachine) {
  const existingMachine = await ask.ask('Please enter the machine ctc info:');
  ctcInfo = parseInt(existingMachine, 10);
} else {
  console.log('OK. We will create a new machine. Please follow the promps.');
  const accMachine = await getAccFromMnemonic(
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
  } = await deployMachine(ctcMachine, payTokenId);
  ctcInfo = mCtcInfo;
  payTokenId = newPayTokId;
}

const shouldCreateRow = await ask.ask(
  'Do you want to create a row?',
  ask.yesno
);

let howManyRows;
if (shouldCreateRow) {
  const numOfRows = await askForNumber(
    'How many rows fo you want to create?',
    3
  );
  howManyRows = numOfRows;
}
let createdRows = 0;
while (createdRows < howManyRows) {
  await createRow(ctcInfo);
  createdRows++;
}

const shouldLoadRow = await ask.ask('Do you want to load a row?', ask.yesno);
if (shouldLoadRow) {
  const isRowLoaded = await loadRow(ctcInfo);
  if (isRowLoaded) console.log('Row Loaded Successfully!');
  process.exit(0);
} else {
  process.exit(0);
}
