import { loadStdlib, ask } from '@reach-sh/stdlib';
import * as backend from './build/index.owner.mjs';

const NETWORK = 'ALGO';
const PROVIDER = 'MainNet';

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

const accDeployer = await getAccFromMnemonic();
const ctc = accDeployer.contract(backend);

console.log('Please Wait...');

// deploy contract
await stdlib.withDisconnect(() =>
  ctc.p.Creator({
    ready: stdlib.disconnect,
  })
);
// set global views for all functions to use
const ctcInfo = await ctc.getInfo();

console.log('');
console.log('************************');
console.log('Contract Deployed!');
console.log({
  ctcInfo: fmtNum(ctcInfo),
});
console.log('************************');
console.log('');

process.exit(0);
