import { loadStdlib, ask } from '@reach-sh/stdlib';
import * as backend from './build/announcer.main.mjs';

const stdlib = loadStdlib('ALGO');
stdlib.setProviderByName('TestNet');

const getAccFromMnemonic = async (
  message = 'Please paste the secret of the deployer:'
) => {
  const mnemonic = await ask.ask(message);
  const fmtMnemonic = mnemonic.replace(/,/g, '');
  const acc = await stdlib.newAccountFromMnemonic(fmtMnemonic);
  return acc;
};

const accDeployer = await getAccFromMnemonic();

const ctcAnnouncer = accDeployer.contract(backend);

// deploy contract
await stdlib.withDisconnect(() =>
  ctcAnnouncer.p.Deployer({
    ready: stdlib.disconnect,
  })
);

const ctcInfo = await ctcAnnouncer.getInfo();
console.log('Contract:', stdlib.bigNumberToNumber(ctcInfo));
