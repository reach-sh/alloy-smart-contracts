import { loadStdlib, ask } from '@reach-sh/stdlib';
import * as vendingMachineBackend from './build/index.vendingMachine.mjs';

const NETWORK = 'ALGO';
const PROVIDER = 'MainNet';

const getRandomNum = (max = 100) => Math.floor(Math.random() * max);
const getRandomBigInt = () => stdlib.bigNumberify(getRandomNum());

const getAccFromMnemonic = async (
  message = 'Please paste the secret of the deployer:'
) => {
  const mnemonic = await ask.ask(message);
  const fmtMnemonic = mnemonic.replace(/,/g, '');
  const acc = await stdlib.newAccountFromMnemonic(fmtMnemonic);
  return acc;
};

export const stdlib = loadStdlib(NETWORK);
stdlib.setProviderByName(PROVIDER);

const fmtNum = n => stdlib.bigNumberToNumber(n);

const createNFT = async acc =>
  await stdlib.launchToken(acc, `Lightning Zeus (season one)`, `ZEUS`, {
    decimals: 0,
  });

const accDeployer = await getAccFromMnemonic();
const ctcMachine = accDeployer.contract(vendingMachineBackend);

const { id: nftId } = await createNFT(accDeployer);

const handleLoad = async () => {
  const rNum = getRandomBigInt();
  const ctcUser = accDeployer.contract(vendingMachineBackend, ctcInfo);
  const { load } = ctcUser.a;
  await load(rNum, 1000);
  console.log('Laoded!');
};

console.log('Please Wait...');

// deploy contract
await stdlib.withDisconnect(() =>
  ctcMachine.p.Deployer({
    ready: stdlib.disconnect,
    NFT: 790565842,
  })
);
// set global views for all functions to use
const { packTok: pTokV, NFT: nftV } = ctcMachine.v;
const [_rawPackTok, rawPackTok] = await pTokV();
const [_rawNFT, rawNFT] = await nftV();
const ctcInfo = await ctcMachine.getInfo();
const NFT_id = await fmtNum(rawNFT);
const packTok = fmtNum(rawPackTok);

await handleLoad();

console.log('');
console.log('************************');
console.log('Contract Deployed!');
console.log({
  ctcInfo: fmtNum(ctcInfo),
  NFT_id,
  packTok,
});
console.log('************************');
console.log('');

process.exit(0);
