import { loadStdlib } from '@reach-sh/stdlib';
import * as machineBackend from '../build/index.machine.mjs';
import * as dispenserBackend from '../build/index.dispenser.mjs';
import { sync, chkScenario } from './utils.mjs';

export const stdlib = loadStdlib('ALGO-devnet');
const { launchToken } = stdlib;

const getRandomNum = (max = 100) => Math.floor(Math.random() * max);
const getRandomBigInt = () => stdlib.bigNumberify(getRandomNum());
const fmtNum = n => stdlib.bigNumberToNumber(n);
export const fmtAddr = addr => stdlib.formatAddress(addr);

const NUM_OF_NFTS = 3;
const NUM_OF_ROWS = 3;

// create the NFT's/tokens
const createNFts = async (acc, amt) => {
  const pms = Array(amt)
    .fill(null)
    .map((_, i) => launchToken(acc, `Cool NFT | edition ${i}`, `NFT${i}`));
  return Promise.all(pms);
};

//create NFT contract
const createNftCtcs = (acc, nfts) =>
  nfts.map(nft => ({
    nft,
    ctc: acc.contract(dispenserBackend),
  }));

// deploy NFT contracts to consensus network
const deployNftCtcs = async (nftHs, machineAddr) => {
  const ctcAddress = [];
  const deploy = nft =>
    new Promise((res, rej) => {
      nft.ctc.p.Dispenser({
        ready: ctc => {
          ctcAddress.push(ctc);
          res();
        },
        nft: nft.nft.id,
        mCtcAddr: machineAddr,
      });
    });
  for (const nftCtc of nftHs) {
    await deploy(nftCtc);
  }
  return ctcAddress;
};

// starting balance
export const bal = stdlib.parseCurrency(10000);

const createRow = async (mCtcInfo, amt = 1, a) => {
  let rowCnt = 0;
  let acc = a;
  let row;
  for (let i = 0; i < amt; i++) {
    acc = a || (await stdlib.newTestAccount(bal));
    const ctcMachine = acc.contract(machineBackend, mCtcInfo);
    const { createRow } = ctcMachine.a;
    const [r, numOfCreatedRows] = await createRow();
    row = r;
    const fmtRn = fmtNum(numOfCreatedRows);
    rowCnt = fmtRn;
  }
  return [rowCnt, acc, row];
};

const loadRow = async (machineAddr, info, acc) => {
  const ctcMachine = acc.contract(machineBackend, info);
  const nfts = await createNFts(acc, NUM_OF_NFTS);
  console.log('creating NFT CTCs...');
  const nftCtcs = createNftCtcs(acc, nfts);
  console.log('deploying NFT CTCs...');
  const nftCtcAdds = await deployNftCtcs(nftCtcs, machineAddr);
  console.log('Loading slots into row(s)...');
  for (const ctc of nftCtcAdds) {
    const [row, rIndex] = await ctcMachine.a.loadRow(ctc, getRandomBigInt());
    const fmtR = fmtNum(row);
    const fmtRi = fmtNum(rIndex);
    console.log(`Loaded slot ${fmtRi} ar row ${fmtR}!`);
  }
  const isRowLoaded = await ctcMachine.a.checkIfLoaded();
  return isRowLoaded;
};

chkScenario('row-create', async (chk, { machineAddr, mCtcInfo }) => {
  const [rowCount, acc, row] = await createRow(mCtcInfo);
  chk('row-count', rowCount, 1);
});
chkScenario('dup-row-create', async (_, { machineAddr, mCtcInfo }, chkErr) => {
  const [rowCount, acc, row] = await createRow(mCtcInfo, 1);
  chkErr('dup-row-create', 'check row exist', () =>
    createRow(mCtcInfo, 1, acc)
  );
});
chkScenario('too-many-rows', async (_, { machineAddr, mCtcInfo }, chkErr) => {
  chkErr('dup-row-create', 'too many rows', () => createRow(mCtcInfo, 10));
});
chkScenario('can-load-row', async (chk, { machineAddr, mCtcInfo }) => {
  const [rowCount, acc, row] = await createRow(mCtcInfo);
  const didLoad = await loadRow(machineAddr, mCtcInfo, acc);
  chk('did load row', didLoad, true);
});

await sync();
