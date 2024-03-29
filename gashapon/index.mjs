import { loadStdlib } from '@reach-sh/stdlib';
import * as machineBackend from './build/index.machine.mjs';
import * as dispenserBackend from './build/index.dispenser.mjs';
import { startTests, describe } from './test-utils.mjs';

export const stdlib = loadStdlib('ALGO');
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
    .map((_, i) =>
      launchToken(acc, `Cool NFT | edition ${i}`, `NFT${i}`, { decimals: 0 })
    );
  const res = await Promise.all(pms);
  return res.map(r => r.id);
};

//create NFT contract
const createNftCtcs = (acc, nftIds) =>
  nftIds.map(nftId => ({
    nftId,
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
        nft: nft.nftId,
        mCtcAddr: machineAddr,
      });
    });
  for (const nftCtc of nftHs) {
    await deploy(nftCtc);
  }
  return ctcAddress;
};

// starting balance
export const bal = stdlib.parseCurrency(1000);

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
  console.log('nftCtcAdds', nftCtcAdds);
  const pms = nftCtcAdds.map(c => ctcMachine.a.loadRow(c, getRandomBigInt()));
  await Promise.all(pms);
  return true;
};

const setupUser = async (ctcInfo, payTokenId, accMachine, existingAcc) => {
  const acc = existingAcc || (await stdlib.newTestAccount(bal));
  await acc.tokenAccept(payTokenId);
  await stdlib.transfer(accMachine, acc, stdlib.parseCurrency(100), payTokenId);

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

    const { insertToken, turnCrank, finishTurnCrank } = await setupUser(
      ctcInfo,
      payTokenId,
      accMachine,
      acc
    );

    const tytBalA = await getTokBal(acc, payTokenId);

    // assign the user an NFT via an NFT contract
    const row = await insertToken(getRandomBigInt());
    const fmtRow = fmtAddr(row);
    console.log('user row', fmtRow);

    const nftCtc = await turnCrank(getRandomBigInt());
    const fmtNftCtc = fmtNum(nftCtc);
    console.log('NFT contract', fmtNftCtc);

    const dCtc = nftContract || (await finishTurnCrank(getRandomBigInt()));
    console.log(`User can now get NFT from contract: ${dCtc}`);

    // get the nft from the user's dispenser contract
    const ctcDispenser = acc.contract(dispenserBackend, dCtc);
    const { nft } = ctcDispenser.v;
    const [_, rawNft] = await nft();
    const fmtNft = fmtNum(rawNft);

    // opt-in to NFT/token
    await acc.tokenAccept(fmtNft);

    // get balances before getting NFT
    const nfBalA = await getTokBal(acc, fmtNft);

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
  const rowAddress = await insertToken(getRandomBigInt());
  const addr = fmtAddr(rowAddress);
  assert.isTrue(id, Boolean(addr));
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
  const { nftCost: vNftCost } = args.v;
  const [l, rawNftCost] = await vNftCost();
  const fmtNftCost = fmtNum(rawNftCost);
  const [{ bals }] = await getNftForUser(
    1,
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  const { before, after } = bals;
  assert.equals(
    'pay token is taken',
    before.payToken - fmtNftCost,
    after.payToken
  );
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
describe('user cannot insert token twice before getting NFT', async (assert, args) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const { insertToken } = await setupUser(
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  await insertToken(getRandomBigInt());
  await assert.error(() => insertToken(getRandomBigInt()));
});

describe('user cannot insert token twice before getting NFT', async (assert, args) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const { insertToken } = await setupUser(
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  await insertToken(getRandomBigInt());
  await assert.error(() => insertToken(getRandomBigInt()));
});
describe('User can insert another token after retrieving NFT', async (assert, args, id) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const { rows } = args.v;
  const maxRowIndex = rows - 1;
  await getNftForUser(1, args.mCtcInfo, args.payTokenId, args.accMachine);
  const { insertToken } = await setupUser(
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  const r = await insertToken(getRandomBigInt());
  const fmtRow = fmtAddr(r);
  assert.isTrue(id, Boolean(fmtRow));
});
describe('can view row map data', async (assert, args) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const { getRow } = args.v;
  const [l, { loadedCtcs, slots, rowToksTkn }] = await getRow(acc);
  const fmtLoadedCtcs = fmtNum(loadedCtcs);
  const fmtNftCtcs = slots.map(c => fmtNum(c[1]));
  const fmtToksTkn = fmtNum(rowToksTkn);
  assert.isTrue(
    'can see row loaded contract count',
    typeof fmtLoadedCtcs == 'number'
  );
  assert.isTrue('can see row nft contracts', typeof fmtNftCtcs == 'object');
  assert.isTrue('can see row toks taken', typeof fmtToksTkn == 'number');
});
describe('can view user map data', async (assert, args) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const { getUser, rows } = args.v;
  const { insertToken, acc: userAcc } = await setupUser(
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  const [l_, { rowIndex: rowIndexBefor }] = await getUser(userAcc);
  assert.equals('no user data before insert token', rowIndexBefor[1], null);
  await insertToken(getRandomBigInt());
  const [l, { rowIndex: rowIndexAfter }] = await getUser(userAcc);
  const fmtRowIAfter = fmtNum(rowIndexAfter[1]);
  assert.isTrue('user has data after insert', fmtRowIAfter <= rows);
});
describe('user can not reset without having empty row', async (assert, args, id) => {
  const [rowCount, [acc]] = await createRow(args.mCtcInfo);
  await loadRow(args.machineAddr, args.mCtcInfo, acc, args.v);
  const { reset, insertToken } = await setupUser(
    args.mCtcInfo,
    args.payTokenId,
    args.accMachine
  );
  await insertToken(getRandomBigInt());
  assert.error(() => reset(getRandomBigInt()));
});

await startTests();
