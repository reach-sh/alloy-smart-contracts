'reach 0.1';
'use strict';

import { getNftCtc } from './utils.rsh';

// 437
const NUM_OF_NFTS = 20;
const NFT_COST = 1;

const dispenserI = {
  setOwner: Fun([Address], Token),
  getNft: Fun([], Token),
};

export const machine = Reach.App(() => {
  const Machine = Participant('Machine', {
    payToken: Token,
    ready: Fun([Contract], Null),
  });
  const api = API({
    load: Fun([Contract], Contract),
    insertToken: Fun([UInt], Contract),
    turnCrank: Fun([], Tuple(Token, Contract)),
  });
  
  const NFT_CTCS = Array.replicate(NUM_OF_NFTS, Maybe(Contract).None());

  init();

  Machine.only(() => {
    const payToken = declassify(interact.payToken);
  });
  Machine.publish(payToken);
  commit();
  Machine.publish();

  const thisContract = getContract();

  const chkCtcValid = ctc => {
    check(typeOf(ctc) == Contract && ctc !== thisContract, 'invalid contract');
  }

  const handlePmt = amt => [0, [amt, payToken]];

  const cMap = new Map(Contract);

  Machine.interact.ready(thisContract);

  const [nftCtcs, R, toksTkn, loadedIndex] = parallelReduce([
    NFT_CTCS,
    digest(0),
    0,
    0,
  ])
    .define(() => {
      // TODO - Jay recommends XORing these before running the digest function.  But there are 3 types here (uint, int, digest) that don't support being XORed together.
      // const getRNum = (N) => digest(N^ R, thisConsensusTime(), thisConsensusSecs())

      // this would not compile when using thisConsensusTime() and thisConsensusSecs()
      // hence the "lastConsensus" things instead
      const getRNum = N =>
        digest(N, R, lastConsensusTime(), lastConsensusSecs());
      const checkCtc = (rNum, user) => {
        const userCtc = cMap[user];
        switch (userCtc) {
          case None:
            assert(true);
          case Some:
            check(typeOf(userCtc) == null, 'user is not registered');
        }
        const rN = getRNum(rNum);
        const nonTakenLength = nftCtcs.length - toksTkn;
        check(nonTakenLength > 0, 'require machine has NFTs');
        const index = rN % nonTakenLength;
        const maxIndex = nonTakenLength - 1;
        check(index <= loadedIndex, 'index is of a loaded ctc');
        const [ctc, newCtcArr] = getNftCtc(nftCtcs, index, maxIndex);
        const c = fromSome(ctc, thisContract)
        chkCtcValid(c);
        check(newCtcArr.length == nftCtcs.length);
        return () => [c, newCtcArr];
      };
      const checkValidUsr = user => {
        const userCtc = cMap[user];
        check(typeOf(userCtc) !== null, 'user has inserted token');
        const c = fromSome(userCtc, thisContract);
        chkCtcValid(c);
        return () => {
          check(typeOf(c) == Contract)
          return c;
        }
      };
    })
    .invariant(balance() === 0 && balance(payToken) / NFT_COST == toksTkn)
    .while(toksTkn < nftCtcs.length)
    .paySpec([payToken])
    .api(
      api.load,
      _ => {
        check(loadedIndex <= nftCtcs.length - 1);
      },
      _ => handlePmt(0),
      (contract, notify) => {
        check(loadedIndex <= nftCtcs.length - 1);
        const newArr = nftCtcs.set(loadedIndex, Maybe(Contract).Some(contract));
        notify(contract);
        return [newArr, R, toksTkn, loadedIndex + 1];
      }
    )
    .api(
      api.insertToken,
      rNum => {
        const _ = checkCtc(rNum, this)();
      },
      _ => handlePmt(NFT_COST),
      (rNum, notify) => {
        const [ctc, newCtcArr] = checkCtc(rNum, this)();
        cMap[this] = ctc;
        notify(ctc);
        return [newCtcArr, R, toksTkn + 1, loadedIndex];
      }
    )
    .api(
      api.turnCrank,
      () => {
        const _ = checkValidUsr(this);
      },
      () => handlePmt(0),
      notify => {
        const ctc = checkValidUsr(this)();
        const dispenserCtc = remote(ctc, dispenserI);
        const nft = dispenserCtc.setOwner(this);
        delete cMap[this];
        notify([nft, ctc]);
        return [nftCtcs, R, toksTkn, loadedIndex];
      }
    );

  transfer(balance()).to(Machine);
  transfer(balance(payToken), payToken).to(Machine);
  commit();
  Anybody.publish();

  commit();
  exit();
});

export const dispenser = Reach.App(() => {
  const Machine = Participant('Machine', {
    ready: Fun([Contract], Null),
    nft: Token,
    mCtcAddr: Address,
  });
  const api = API(dispenserI);
  const v = View({
    nft: Token,
  });

  init();
  Machine.publish();
  commit();

  Machine.only(() => {
    const nft = declassify(interact.nft);
    const mCtcAddr = declassify(interact.mCtcAddr);
  });
  Machine.publish(nft, mCtcAddr);
  v.nft.set(nft);
  commit();
  Machine.pay([[1, nft]]);

  check(balance(nft) == 1);

  Machine.interact.ready(getContract());

  commit();

  const [[owner], k2] = call(api.setOwner).assume(nOwner => {
    check(this == mCtcAddr);
    check(nOwner !== mCtcAddr);
    check(nOwner !== Machine);
  });
  check(this == mCtcAddr);
  check(owner !== mCtcAddr);
  check(owner !== Machine);
  k2(nft);

  commit();

  const [[], k3] = call(api.getNft).assume(() => {
    check(this == owner);
    check(balance(nft) == 1);
  });
  check(this == owner);
  check(balance(nft) == 1);
  transfer(1, nft).to(this);
  check(balance(nft) == 0);
  k3(nft);

  transfer(balance()).to(Machine);
  transfer(balance(nft), nft).to(Machine);
  commit();
});
