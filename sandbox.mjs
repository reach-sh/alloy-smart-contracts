import { loadStdlib } from '@reach-sh/stdlib';
import * as machineBackend from './build/index.machine.mjs';
import fetch from 'node-fetch';
import {
  deployBulkCtcs,
  createNftCtcs,
  stdlib,
  createMockNFTs,
} from './utils.mjs';

const INDEXER_URL = 'https://testnet-idx.algonode.cloud/v2';
const MACHINE_CTC_INFO = 93146306;
const MACHINE_ADDR =
  '4OYVQDBFCXDNDMPPCCHDSZQDRHKEUMDYCZ5YE7VQNZYG6DCWLSO23HTUGE';
const fmtCtcInfo = parseInt(`${MACHINE_CTC_INFO}`, 10);
const MNEMONIC =
  '<replace-me>';

const fmtMnemonic = MNEMONIC.replace(/,/g, '');
const acc = await stdlib.newAccountFromMnemonic(fmtMnemonic);

async function getAccountAssets(addr) {
  const accountResp = await fetch(`${INDEXER_URL}/accounts/${addr}`);
  const { account } = await accountResp.json();
  const key = 'created-assets';
  const assets = account[key];
  let nfts = assets;
  return nfts;
}

const getRandomNum = (max = 100) => Math.floor(Math.random() * max);
const getRandomBigInt = () => stdlib.bigNumberify(getRandomNum());

const loadRow = async nftsToLoad => {
  const ctcMachine = acc.contract(machineBackend, fmtCtcInfo);
  const pms = nftsToLoad.map(c => ctcMachine.a.loadRow(c, getRandomBigInt()));
  await Promise.all(pms);
  return true;
};

// const accAddr = acc.networkAccount.addr;
// const createdAssets = await getAccountAssets(accAddr);
// const createdAssetIds = createdAssets.map(ass => ass.index);
// const slicedAssets = createdAssetIds.slice(0, 100);
// console.log('slicedAssets', slicedAssets.length);
// const assetIdsAsBigNum = slicedAssets.map(assId => stdlib.bigNumberify(assId));

// console.log('loading row...');
// const test = await loadRow(assetIdsAsBigNum);
// console.log('YAY');
console.log('starting...');
const nfts = await createMockNFTs(acc, 20);
console.log('nfts minted!');
// const nftCtcs = createNftCtcs(acc, nfts);
// console.log('nft contracts created!');
// const deployedCtcs = await deployBulkCtcs(nftCtcs, MACHINE_ADDR);
// console.log('yay', deployedCtcs.length);