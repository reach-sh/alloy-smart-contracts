import { loadStdlib } from '@reach-sh/stdlib';
import * as machineBackend from './build/index.machine.mjs';
import * as dispenserBackend from './build/index.dispenser.mjs';
import { startTests, describe } from './test-utils.mjs';

export const stdlib = loadStdlib('ALGO-devnet');
const { launchToken } = stdlib;

export const fmtAddr = addr => stdlib.formatAddress(addr);
export const fmtNum = n => stdlib.bigNumberToNumber(n);
const getRandomNum = (max = 100) => Math.floor(Math.random() * max);
const getRandomBigInt = () => stdlib.bigNumberify(getRandomNum());
// helper for getting formatted token balance
const getTokBal = async (acc, tok) => {
  const balB = await stdlib.balanceOf(acc, tok);
  const balA = fmtNum(balB);
  return balA;
};

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
  const rows = [];
  for (let i = 0; i < amt; i++) {
    const acc = a || (await stdlib.newTestAccount(bal));
    const ctcMachine = acc.contract(machineBackend, mCtcInfo);
    const { createRow } = ctcMachine.a;
    const [_, numOfCreatedRows] = await createRow();
    rows.push(acc);
    const fmtRn = fmtNum(numOfCreatedRows);
    rowCnt = fmtRn;
  }
  return [rowCnt, rows];
};

const loadRow = async (machineAddr, info, acc, views) => {
  const { slots } = views;
  const ctcMachine = acc.contract(machineBackend, info);
  const nfts = await createNFts(acc, slots);
  const nftCtcs = createNftCtcs(acc, nfts);
  const nftCtcAdds = await deployNftCtcs(nftCtcs, machineAddr);
  for (const ctc of nftCtcAdds) {
    const [row, rIndex] = await ctcMachine.a.loadRow(ctc, getRandomBigInt());
    const fmtR = fmtNum(row);
    const fmtRi = fmtNum(rIndex);
  }
  const isRowLoaded = await ctcMachine.a.checkIfLoaded();
  return isRowLoaded;
};

const setupUser = async (ctcInfo, payTokenId, accMachine, existingAcc) => {
  const acc = existingAcc || (await stdlib.newTestAccount(bal));
  await acc.tokenAccept(payTokenId);
  await stdlib.transfer(accMachine, acc, 100, payTokenId);

  const ctcUser = acc.contract(machineBackend, ctcInfo);
  const apis = ctcUser.a;
  return {
    ...apis,
    acc,
  };
};

const getNftForUser = async (
  amt = 1,
  ctcInfo,
  payTokenId,
  accMachine,
  existingAcc,
  nftContract
) => {
  const reponses = [];
  for (let i = 0; i < amt; i++) {
    const acc = existingAcc || (await stdlib.newTestAccount(bal));
    await acc.tokenAccept(payTokenId);
    await stdlib.transfer(accMachine, acc, 100, payTokenId);

    const {
      insertToken,
      turnCrank,
      finishTurnCrank,
      setOwner: assignNft,
    } = await setupUser(ctcInfo, payTokenId, accMachine, acc);

    const tytBalA = await getTokBal(acc, payTokenId);

    // assign the user an NFT via an NFT contract
    const rowIndex = await insertToken(getRandomBigInt());
    const fmtRowI = fmtNum(rowIndex);

    const row = await turnCrank(getRandomBigInt());
    const fmtRow = fmtAddr(row);

    const dCtc = nftContract || (await finishTurnCrank(getRandomBigInt()));
    const fmtN = fmtNum(dCtc);

    const ctcDispenser = acc.contract(dispenserBackend, dCtc);

    // get the nft from the user's dispenser contract
    const { nft } = ctcDispenser.v;
    const [_, rawNft] = await nft();
    const fmtNft = fmtNum(rawNft);

    // opt-in to NFT/token
    await acc.tokenAccept(fmtNft);

    // get balances before getting NFT
    const nfBalA = await getTokBal(acc, fmtNft);

    await assignNft();

    // // get NFT
    const usrCtcDispenser = acc.contract(dispenserBackend, dCtc);
    const { getNft } = usrCtcDispenser.a;
    await getNft();

    // get balances after getting NFT
    const tytBalB = await getTokBal(acc, payTokenId);
    const nfBalB = await getTokBal(acc, fmtNft);
    const newResponse = {
      bals: {
        before: {
          payToken: tytBalA,
          nft: nfBalA,
        },
        after: {
          payToken: tytBalB,
          nft: nfBalB,
        },
      },
      nftCtc: dCtc,
      acc,
    };
    reponses.push(newResponse);
  }
  return reponses;
};

// unit tests
describe('owner can create row', async (assert, { mCtcInfo, v }, id) => {
  const [rowCount] = await createRow(mCtcInfo);
  assert.equals(id, rowCount, 1);
});
describe('owner can load row', async (assert, {
  machineAddr,
  mCtcInfo,
  v,
}, id) => {
  const [rowCount, [acc]] = await createRow(mCtcInfo);
  const didLoad = await loadRow(machineAddr, mCtcInfo, acc, v);
  assert.equals(id, didLoad, true);
});
describe('no dupe row create', async (assert, { mCtcInfo }, id) => {
  const [rowCount, [acc]] = await createRow(mCtcInfo, 1);
  await assert.error(id, () => createRow(mCtcInfo, 1, acc));
});
describe('prevent too many row creations', async (assert, {
  mCtcInfo,
  v,
}, id) => {
  const { rows } = v;
  await assert.error(id, () => createRow(mCtcInfo, rows + 1));
});
describe('user can insert token', async (assert, args, id) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const { rows } = args.v;
  const maxRowIndex = rows - 1;
  const { insertToken } = await setupUser(
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  const rawRowIndex = await insertToken(getRandomBigInt());
  const fmtRindex = fmtNum(rawRowIndex);
  assert.isTrue(id, fmtRindex <= maxRowIndex);
});
describe('user can not turn crank without inserting token', async (assert, args, id) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const { turnCrank } = await setupUser(
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  await assert.error(id, () => turnCrank(getRandomBigInt()));
});
describe('user can not finish crank without inserting token', async (assert, args, id) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const { finishTurnCrank } = await setupUser(
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  await assert.error(id, () => finishTurnCrank(getRandomBigInt()));
});
describe('user can get nft', async (assert, args) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const [{ bals }] = await getNftForUser(
    1,
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  const { before, after } = bals;
  assert.equals('pay token is taken', before.payToken - 1, after.payToken);
  assert.equals('1 nft is given to user', before.nft + 1, after.nft);
});
describe('user can not get nft twice', async (assert, args) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const [{ nftCtc, acc: existingAcc }] = await getNftForUser(
    1,
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  await assert.error('same user cannot get already received NFT', () =>
    getNftForUser(
      1,
      args.mCtcInfo,
      args.payTokenId,
      args.accMachine,
      existingAcc,
      nftCtc
    )
  );
  await assert.error('new user cannot get already received NFT', () =>
    getNftForUser(
      1,
      args.mCtcInfo,
      args.payTokenId,
      args.accMachine,
      null,
      nftCtc
    )
  );
});
describe('user can not add NFT to slot', async (assert, args, id) => {
  const useracc = await stdlib.newTestAccount(bal);
  await createRow(args.mCtcInfo);
  await assert.error(id, () =>
    loadRow(args.machineAddr, args.mCtcInfo, useracc, args.v)
  );
});
describe('all nfts can be retrieved', async (assert, args, id) => {
  const { rows, slots } = args.v;
  const totalNumberOfAvailNFTs = slots * rows;
  const [rowCount, createdRows] = await createRow(args.mCtcInfo, rows);
  for (const r of createdRows) {
    await loadRow(args.machineAddr, args.mCtcInfo, r, args.v);
  }
  const res = await getNftForUser(
    totalNumberOfAvailNFTs,
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  assert.equals(id, res.length, totalNumberOfAvailNFTs);
});
describe('user cannot claim already assigned NFT', async (assert, args) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const {
    insertToken,
    turnCrank,
    finishTurnCrank,
    setOwner: assignNft,
    acc: userAccount,
  } = await setupUser(args.mCtcInfo, args.payTokenId, args.accMachine);
  await insertToken(getRandomBigInt());
  await turnCrank(getRandomBigInt());
  const dCtc = await finishTurnCrank(getRandomBigInt());
  const ctcDispenser = userAccount.contract(dispenserBackend, dCtc);
  // get the nft from the user's dispenser contract
  const { nft } = ctcDispenser.v;
  const [_, rawNft] = await nft();
  const fmtNft = fmtNum(rawNft);
  await userAccount.tokenAccept(fmtNft);

  const user2 = await stdlib.newTestAccount(bal);
  await user2.tokenAccept(fmtNft);
  const usr2CtcDispenser = user2.contract(dispenserBackend, dCtc);
  const { getNft: badActorGetNft } = usr2CtcDispenser.a;
  await assert.error(() => badActorGetNft());
});

await startTests();
