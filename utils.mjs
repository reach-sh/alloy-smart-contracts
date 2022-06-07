import { loadStdlib, ask } from '@reach-sh/stdlib';
import * as dispenserBackend from './build/index.dispenser.mjs';
import * as machineBackend from './build/index.machine.mjs';
import fetch from 'node-fetch';

const INDEXER_URL = 'https://testnet-idx.algonode.cloud/v2';
const NETWORK = 'ALGO';
const PROVIDER = 'TestNet';

export const stdlib = loadStdlib(NETWORK);
stdlib.setProviderByName(PROVIDER);
// stdlib.setMinMillisBetweenRequests(1);

const { launchToken } = stdlib;

export const fmtAddr = addr => stdlib.formatAddress(addr);
export const fmtNum = n => stdlib.bigNumberToNumber(n);
export const getRandomNum = (max = 100) => Math.floor(Math.random() * max);
export const getRandomBigInt = () => stdlib.bigNumberify(getRandomNum());
// helper for getting formatted token balance
export const getTokBal = async (acc, tok) => {
  const balB = await stdlib.balanceOf(acc, tok);
  const balA = fmtNum(balB);
  return balA;
};

export const createRowAccounts = async amt => {
  const accountsToMake = Array(amt).fill(null);
  const pms = accountsToMake.map(_ => stdlib.createAccount());
  return await Promise.all(pms);
};

// starting balance
export const bal = stdlib.parseCurrency(1000);

// create the NFT's/tokens
export const createMockNFTs = async (acc, amt) => {
  let p;
  const tokens = [];
  const untilDone = new Promise((resolve, reject) => {
    p = { resolve, reject };
  });
  const done = p.resolve;
  const tokensToMint = Array(amt).fill(null);
  tokensToMint.forEach((_, i) => {
    setTimeout(function () {
      const tokPms = launchToken(acc, `Cool NFT | edition ${i}`, `NFT${i}`, {
        decimals: 0,
      });
      tokens.push(tokPms);
      if (i === tokensToMint.length - 1) done();
    }, i * 100);
  });
  await untilDone;
  const res = await Promise.all(tokens);
  return res.map(r => r.id);
};

//create NFT contract
export const createNftCtcs = (acc, nftIds) =>
  nftIds.map(nftId => ({
    nftId,
    ctc: acc.contract(dispenserBackend),
  }));

// deploy NFT contracts to consensus network
export const deployBulkCtcs = async (nftHs, machineAddr) => {
  let p;
  const ctcAddress = [];
  const untilDone = new Promise((resolve, reject) => {
    p = { resolve, reject };
  });
  const done = p.resolve;
  nftHs.forEach((nft, i) =>
    setTimeout(function () {
      nft.ctc.p.Dispenser({
        ready: ctc => {
          ctcAddress.push(ctc);
          if (ctcAddress.length === nftHs.length) done();
        },
        nft: nft.nftId,
        mCtcAddr: machineAddr,
      });
    }, i * 250)
  );
  await untilDone;
  return ctcAddress;
};

export const askForNumber = async (msg, max) => {
  let r;
  while (!r || r > max || r <= 0) {
    const howMany = await ask.ask(msg);
    if (isNaN(howMany) || Number(howMany) > max || Number(howMany) <= 0) {
      console.log(
        `* Please enter an integer that is greater than 0 and less than ${max}.`
      );
    } else {
      r = Number(howMany);
    }
  }
  return r;
};

export const deployMachine = async (ctcMachine, payTokenId) => {
  console.log('deploying machine contract...');
  let fmtRowNum;
  let fmtSlotNum;
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
      fmtRowNum = fmtNum(rawRowNum[1]);
      fmtSlotNum = fmtNum(rawSlotNum[1]);
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

  return {
    mCtcInfo,
    machineAddr,
    payTokenId,
    numOfRows: fmtRowNum,
    numOfSlots: fmtSlotNum,
  };
};

export async function getAccountAssets(addr, user) {
  const accountResp = await fetch(`${INDEXER_URL}/accounts/${addr}`);
  const { account } = await accountResp.json();
  const assets = account['assets'];
  const createdAssets = account['created-assets'];
  return { assets, createdAssets };
}

export const getAccFromMnemonic = async (
  message = 'Please paste the mnemonic of the user:'
) => {
  const mnemonic = await ask.ask(message);
  const fmtMnemonic = mnemonic.replace(/,/g, '');
  const acc = await stdlib.newAccountFromMnemonic(fmtMnemonic);
  return acc;
};

export const createRow = async (rowAcc, mCtcInfo, machineAcc) => {
  const ctcMachine = rowAcc.contract(machineBackend, mCtcInfo);
  const { createRow: ctcCreateRow } = ctcMachine.a;
  const [_, numOfCreatedRows] = await ctcCreateRow();
  const fmtRn = fmtNum(numOfCreatedRows);
  console.log('Created row:', fmtRn);
};

export const loadRow = async (acc, nftCtcs, fmtCtcInfo) => {
  const ctcMachine = acc.contract(machineBackend, fmtCtcInfo);
  const pms = nftCtcs.map(c => ctcMachine.a.loadRow(c, getRandomBigInt()));
  await Promise.all(pms);
  return true;
};

export const launchPayToken = async accMachine => {
  console.log('Launching pay token...');
  const { id: nPayTokenId } = await launchToken(
    accMachine,
    'Reach Thank You',
    'RTYT',
    { decimals: 0 }
  );
  return fmtNum(nPayTokenId);
};
