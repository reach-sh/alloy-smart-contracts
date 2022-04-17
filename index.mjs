import { loadStdlib } from '@reach-sh/stdlib';
import * as machineBackend from './build/index.machine.mjs';
import * as dispenserBackend from './build/index.dispenser.mjs';

const stdlib = loadStdlib('ALGO-devnet');
const { launchToken } = stdlib;

const NUM_OF_NFTS = 2;
const NUM_OF_ROWS = 10;

// starting balance
const bal = stdlib.parseCurrency(10000);

const getRandomNum = () => Math.floor(Math.random() * (100 - 0 + 1) + 0);;

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

// TODO: clean this function up
// deploy NFT contracts to consensus network
const deployNftCtcs = (nftHs, machineAddr) => {
  return new Promise((resolve, reject) => {
    let ctcAddress = [];
    let i = 0;
    const deployCtc = () => {
      if (i === nftHs.length) {
        resolve(ctcAddress);
        return;
      }
      nftHs[i].ctc.p.Dispenser({
        ready: ctc => {
          ctcAddress.push(ctc);
          deployCtc(i++);
        },
        nft: nftHs[i].nft.id,
        mCtcAddr: machineAddr,
      });
    };
    deployCtc();
  });
};

// load NFT contracts in machine contract
const loadRow = async (machineAddr, info, amount) => {
  for (let i = 0; i < amount; i++) {
    const accAltMachine = await stdlib.newTestAccount(bal);
    const ctcMachine = accAltMachine.contract(machineBackend, info);
    console.log('');
    console.log('-- Starting row loading --');
    console.log('');
    console.log('creating NFTS...');
    const nfts = await createNFts(accAltMachine, NUM_OF_NFTS);
    console.log('creating NFT CTCs...');
    const nftCtcs = createNftCtcs(accAltMachine, nfts);
    console.log('deploying NFT CTCs...');
    const nftCtcAdds = await deployNftCtcs(nftCtcs, machineAddr);
    console.log('Loading slots into row(s)...');
    for (const ctc of nftCtcAdds) {
      const [row, rIndex] = await ctcMachine.a.loadRow(
        ctc,
        stdlib.bigNumberify(getRandomNum())
      );
      const fmtR = stdlib.bigNumberToNumber(row);
      const fmtRi = stdlib.bigNumberToNumber(rIndex);
      console.log(`Loaded slot ${fmtRi} ar row ${fmtR}!`);
    }
    const isRowLoaded = await ctcMachine.a.checkIfLoaded();
    if (isRowLoaded) {
      console.log('');
      console.log('Successfully loaded Row!');
      console.log('');
    } else {
      console.log('Error: problem loading row.');
    }
  }
};

// helper for getting formatted token balance
const getTokBal = async (acc, tok) => {
  const balB = await stdlib.balanceOf(acc, tok);
  const balA = stdlib.bigNumberToNumber(balB);
  return balA;
};

// create users
const accMachine = await stdlib.newTestAccount(bal);
// create machine contract
const ctcMachine = accMachine.contract(machineBackend);

// create pay token
const { id: payTokenId } = await launchToken(
  accMachine,
  'Reach Thank You',
  'RTYT'
);

const getNftForUser = async (existingAcc, nftCtc) => {
  const info = await ctcMachine.getInfo();

  const acc = existingAcc || (await stdlib.newTestAccount(bal));
  await acc.tokenAccept(payTokenId);
  await stdlib.transfer(accMachine, acc, 100, payTokenId);

  const ctcUser = acc.contract(machineBackend, info);
  const { insertToken, turnCrank, finishTurnCrank } = ctcUser.a;

  // assign the user an NFT via an NFT contract
  const rNum = getRandomNum();
  const row = await insertToken(stdlib.bigNumberify(rNum));
  const fmtRow = stdlib.formatAddress(row);
  console.log('Your row id:', fmtRow);

  const rNum1 = getRandomNum();
  const nCtc = await turnCrank(stdlib.bigNumberify(rNum1));
  const dCtc = stdlib.bigNumberToNumber(nCtc);
  console.log('Your dispenser contract is:', dCtc);

  const ctcDispenser = acc.contract(dispenserBackend, nftCtc || dCtc);

  // get the nft from the user's dispenser contract
  const { nft } = ctcDispenser.v;
  const [_, rawNft] = await nft();
  const fmtNft = stdlib.bigNumberToNumber(rawNft);
  console.log('NFT to get:', fmtNft);

  // opt-in to NFT/token
  await acc.tokenAccept(fmtNft);

  // get balances before getting NFT
  const tytBalA = await getTokBal(acc, payTokenId);
  const nfBalA = await getTokBal(acc, fmtNft);
  console.log('balance of TYT Token before', tytBalA);
  console.log('balance of NFT before', nfBalA);

  // // set the owner of the NFT contract to the uer so they can get it
  const rNum2 = getRandomNum();
  const n = await finishTurnCrank(rNum2);
  const fmtN = stdlib.bigNumberToNumber(n);
  console.log(`Can now get nft ${fmtN} from contract ${dCtc}.`);

  // // get NFT
  const usrCtcDispenser = acc.contract(dispenserBackend, dCtc);
  const { getNft } = usrCtcDispenser.a;
  await getNft();

  // get balances after getting NFT
  const tytBalB = await getTokBal(acc, payTokenId);
  const nfBalB = await getTokBal(acc, fmtNft);
  console.log('balance of TYT Token after', tytBalB);
  console.log('balance of NFT after', nfBalB);

  return [dCtc, fmtNft];
};

const onAppDeploy = async () => {
  const info = await ctcMachine.getInfo();

  // get machine contract address
  const rawMachineAddr = await ctcMachine.getContractAddress();
  const machineAddr = stdlib.formatAddress(rawMachineAddr);

  // create NFT's, NFT dispenser contracts, and deploy NFT dispenser contracts
  await loadRow(machineAddr, info, NUM_OF_ROWS);

  await getNftForUser();
  await getNftForUser();
  await getNftForUser();
  await getNftForUser();
  await getNftForUser();
  await getNftForUser();
  await getNftForUser();
  await getNftForUser();
  await getNftForUser();
  await getNftForUser();

  process.exit(0);
};

await Promise.all([
  ctcMachine.p.Machine({
    payToken: payTokenId,
    ready: onAppDeploy,
  }),
]);
