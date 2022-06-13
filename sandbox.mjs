import { ask } from '@reach-sh/stdlib';
import * as machineBackend from './build/index.machine.mjs';
import {
  deployBulkCtcs,
  createNftCtcs,
  stdlib,
  createMockNFTs,
  getAccFromMnemonic,
  getAccountAssets,
} from './utils.mjs';

const MACHINE_CTC_INFO = 95221985;
const MACHINE_ADDR =
  '4OYVQDBFCXDNDMPPCCHDSZQDRHKEUMDYCZ5YE7VQNZYG6DCWLSO23HTUGE';
const fmtCtcInfo = parseInt(`${MACHINE_CTC_INFO}`, 10);

const acc = await getAccFromMnemonic(
  'Please enter the mnemonic of an account:'
);

const getRandomNum = (max = 100) => Math.floor(Math.random() * max);
const getRandomBigInt = () => stdlib.bigNumberify(getRandomNum());

const loadRow = async nftCtcsToLoad => {
  console.log('Loading row...');
  const ctcMachine = acc.contract(machineBackend, fmtCtcInfo);
  const pms = nftCtcsToLoad.map(c =>
    ctcMachine.a.loadRow(c, getRandomBigInt())
  );
  await Promise.all(pms);
  return true;
};

const getAccAssetIds = async () => {
  console.log('getting assets from account...');
  const accAddr = acc.networkAccount.addr;
  const { createdAssets } = await getAccountAssets(accAddr);
  const createdAssetIds = createdAssets.map(ass => ass.index);
  const slicedAssets = createdAssetIds.slice(0, 100);
  const assetIdsAsBigNum = slicedAssets.map(assId =>
    stdlib.bigNumberify(assId)
  );
  return assetIdsAsBigNum;
};

const shouldCreateMockNFTS = await ask.ask(
  `Do you want to create NFTs for account: ${acc.networkAccount.addr}?`,
  ask.yesno
);

let nfts;
if (shouldCreateMockNFTS) {
  nfts = await createMockNFTs(acc, 50);
} else {
  nfts = await getAccAssetIds();
}

const keepGoing = await ask.ask(
  `Do you want to continue with deploying nft contracts?`,
  ask.yesno
);
if (!keepGoing) process.exit(0);

const nftCtcs = createNftCtcs(acc, nfts);
const deployedNftCtcs = await deployBulkCtcs(nftCtcs, MACHINE_ADDR);
await loadRow(deployedNftCtcs);

console.log('done!');

process.exit(0);
