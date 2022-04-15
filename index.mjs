import { loadStdlib } from '@reach-sh/stdlib';
import * as machineBackend from './build/index.machine.mjs';
import * as dispenserBackend from './build/index.dispenser.mjs';

const stdlib = loadStdlib('ALGO-devnet');
const { launchToken } = stdlib;

const NUM_OF_NFTS = 50;

// starting balance
const bal = stdlib.parseCurrency(10000);

const getRandomNum = () => Math.floor(Math.random() * 20);

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
      nftHs[i].ctc.p.Machine({
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
const loadNfts = async nftCtcAdds => {
  const pms = nftCtcAdds.map(ctcAdd => ctcMachine.a.load(ctcAdd));
  const resolved = await Promise.all(pms);
  const fmted = resolved.map(res => stdlib.bigNumberToNumber(res));
  return fmted;
};

// helper for getting formatted token balance
const getTokBal = async (acc, tok) => {
  const balB = await stdlib.balanceOf(acc, tok);
  const balA = stdlib.bigNumberToNumber(balB);
  return Promise.resolve(balA);
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
  const { insertToken, turnCrank } = ctcUser.a;

  // assign the user an NFT via an NFT contract
  const rNum = getRandomNum();
  const dispenserCtc = await insertToken(stdlib.bigNumberify(rNum));
  const fmtCtc = stdlib.bigNumberToNumber(dispenserCtc);
  console.log('Your dispenser ctc is:', fmtCtc);

  const ctcDispenser = acc.contract(dispenserBackend, nftCtc || dispenserCtc);

  // get the nft from the user's dispenser contract
  const { nft } = ctcDispenser.v;
  const [_, rawNft] = await nft();
  const fmtNft = stdlib.bigNumberToNumber(rawNft);
  console.log('NFT to get:', fmtNft);

  // opt-in to NFT/token
  await acc.tokenAccept(fmtNft);
  const fmtCtcWnft = stdlib.bigNumberToNumber(dispenserCtc);
  console.log(
    'The dispenser contract is ready for you to get your NFT:',
    fmtCtcWnft
  );

  // get balances before getting NFT
  const tytBalA = await getTokBal(acc, payTokenId);
  const nfBalA = await getTokBal(acc, fmtNft);
  console.log('balance of TYT Token before', tytBalA);
  console.log('balance of NFT before', nfBalA);

  // set the owner of the NFT contract to the uer so they can get it
  await turnCrank();

  // get NFT
  const usrCtcDispenser = acc.contract(dispenserBackend, dispenserCtc);
  const { getNft } = usrCtcDispenser.a;
  await getNft();

  // get balances after getting NFT
  const tytBalB = await getTokBal(acc, payTokenId);
  const nfBalB = await getTokBal(acc, fmtNft);
  console.log('balance of TYT Token after', tytBalB);
  console.log('balance of NFT after', nfBalB);

  return [fmtCtc, fmtNft];
};

const onAppDeploy = async () => {
  // get machine contract address
  const rawMachineAddr = await ctcMachine.getContractAddress();
  const machineAddr = stdlib.formatAddress(rawMachineAddr);

  // create NFT's, NFT dispenser contracts, and deploy NFT dispenser contracts
  const nfts = await createNFts(accMachine, NUM_OF_NFTS);
  const nftCtcs = createNftCtcs(accMachine, nfts);
  const nftCtcAdds = await deployNftCtcs(nftCtcs, machineAddr);
  await loadNfts(nftCtcAdds);

  const [nftCtc1, nft1] = await getNftForUser();
  const [nftCtc2, nft2] = await getNftForUser();
  const [nftCtc, nft] = await getNftForUser();
  process.exit(0);
};

await ctcMachine.p.Machine({
  payToken: payTokenId,
  ready: onAppDeploy,
});
