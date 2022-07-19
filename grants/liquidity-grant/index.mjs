import { loadStdlib } from '@reach-sh/stdlib';
import * as backend from './build/index.owner.mjs';
import * as announcerBackend from './build/announcer.main.mjs';

const stdlib = loadStdlib('ALGO');
const bal = stdlib.parseCurrency(1000);
const userAccs = await stdlib.newTestAccounts(3, bal);
const fmtAddr = addr => stdlib.formatAddress(addr);
const fmtNum = n => stdlib.bigNumberToNumber(n);

const accDeployer = userAccs[0];
const accRenter = userAccs[1];

const ctcMachine = accDeployer.contract(backend);
const ctcMachin2 = accDeployer.contract(backend);
const announcer = accDeployer.contract(announcerBackend);

// deploy contract
await stdlib.withDisconnect(() =>
  announcer.p.Deployer({
    ready: stdlib.disconnect,
  })
);
const annCTCInfo = await announcer.getInfo();

const acc3 = userAccs[2];
const ctcAnnouncer = acc3.contract(
  announcerBackend,
  stdlib.bigNumberToNumber(annCTCInfo)
);
const {
  e: { Announce },
  a: annApi,
} = ctcAnnouncer;

const startAnnouncer = async () => {
  console.log('announcer started...');
  const accObs = await r.createAccount();
  const ctcAnnObs = accObs.contract(announcerBin, ctcInfoAnn);
  const check = ({ what }) => {
    const ctcInfo = what[0];
    const fmtCtc = stdlib.bigNumberToNumber(ctcInfo);
    console.log('announced:', fmtCtc);
  };
  await Announce.monitor(check);
};
startAnnouncer();

// deploy contract
await stdlib.withDisconnect(() =>
  ctcMachine.p.Creator({
    name: 'Zeaus',
    symbol: 'ZEUS',
    ready: stdlib.disconnect,
  })
);

// deploy contract
await stdlib.withDisconnect(() =>
  ctcMachin2.p.Creator({
    name: 'Zeaus',
    symbol: 'ZEUS',
    ready: stdlib.disconnect,
  })
);

const ctcInfo = await ctcMachine.getInfo();
const ctcInfo2 = await ctcMachin2.getInfo();
// testing announcer
await annApi.announce(ctcInfo);
await annApi.announce(ctcInfo2);
const { a: a1 } = ctcMachine;
await a1.makeAvailable();

const ctcRenter = accRenter.contract(backend, ctcInfo);
const { a: a2, v } = ctcRenter;
const [_a, o] = await v.owner();
console.log('o', fmtAddr(o));
const rentCtc = await a2.rent();
const [_b, o1] = await v.owner();
const [_c, rt] = await v.endRentTime();
const fmtEndBlock = stdlib.bigNumberToNumber(rt);
const time = await stdlib.getNetworkTime();
console.log('time', fmtNum(time));
console.log('fmtEndBlock', fmtEndBlock);
console.log('o', fmtAddr(o1));
