'reach 0.1';
'use strict';

// 437
const NUM_OF_NFTS = 10;
const NUM_OF_ROWS = 3;
const NFT_COST = 1;

const defNfts = Array.replicate(NUM_OF_NFTS, Maybe(Contract).None());

const RowN = Address;
const Row = Object({
  nftCtcs: Array(Maybe(Contract), NUM_OF_NFTS),
  loadedIndex: UInt,
  rowToksTkn: UInt,
});
const defRow = {
  nftCtcs: defNfts,
  loadedIndex: 0,
  rowToksTkn: 0,
};

const dispenserI = {
  setOwner: Fun([Address], Token),
  getNft: Fun([], Token),
};

export const machine = Reach.App(() => {
  setOptions({ connectors: [ALGO] });

  const Machine = Participant('Machine', {
    payToken: Token,
    ready: Fun([Contract], Null),
  });
  const api = API({
    // createRow: Fun([Address], Null),
    loadRow: Fun([Contract, UInt], Tuple(UInt, UInt)),
    checkIfLoaded: Fun([], Bool),
    insertToken: Fun([UInt], RowN),
    turnCrank: Fun([UInt], Contract),
    finishTurnCrank: Fun([UInt], Token),
  });

  init();

  Machine.only(() => {
    const payToken = declassify(interact.payToken);
  });
  Machine.publish(payToken);

  const uMap = new Map(
    Object({
      nftContract: Maybe(Contract),
      row: Maybe(RowN),
    })
  );
  const defUsr = {
    nftContract: Maybe(Contract).None(),
    row: Maybe(RowN).None(),
  };
  const rowMap = new Map(Row);
  const rPicker = Array.replicate(NUM_OF_ROWS, Maybe(Address).None());

  const thisContract = getContract();

  // const chkCtcValid = ctc => {
  //   check(typeOf(ctc) == Contract && ctc !== thisContract, 'invalid contract');
  // };

  const handlePmt = amt => [0, [amt, payToken]];

  const getRow = row => rowMap[row];

  Machine.interact.ready(thisContract);

  const [R, toksTkn, rows, loadedRows] = parallelReduce([
    digest(0),
    0,
    rPicker,
    0,
  ])
    .define(() => {
      const getRKey = i => {
        const rKey = rows[i];
        check(isSome(rKey), 'there is a row');
        const r = fromSome(rKey, Machine);
        check(r !== Machine, 'is any');
        return r;
      };
      // TODO - Jay recommends XORing these before running the digest function.  But there are 3 types here (uint, int, digest) that don't support being XORed together.
      // const getRNum = (N) => digest(N^ R, thisConsensusTime(), thisConsensusSecs())

      // this would not compile when using thisConsensusTime() and thisConsensusSecs()
      // hence the "lastConsensus" things instead
      const getRNum = N =>
        digest(N, R, lastConsensusTime(), lastConsensusSecs());
      const getNftCtc = (arr, i, sz) => {
        const k = sz == 0 ? 0 : sz - 1;
        const ip = i % sz;
        const ctc = arr[ip];
        const defCtc = Maybe(Contract).None();
        const newArr = Array.set(arr, ip, arr[k]);
        const nullEndArr = Array.set(newArr, k, defCtc);
        return [ctc, nullEndArr];
      };
      // const checkCtc = (rNum, user) => {
      //   // const userCtc = uMap[user];
      //   // switch (userCtc) {
      //   //   case None:
      //   //     assert(true);
      //   //   case Some:
      //   //     check(typeOf(userCtc) == null, 'user is not registered');
      //   // }
      //   const rN = getRNum(rNum);
      //   const nonTakenLength = nftCtcs.length - toksTkn;
      //   check(nonTakenLength > 0, 'require machine has NFTs');
      //   const index = rN % nonTakenLength;
      //   const maxIndex = nonTakenLength - 1;
      //   check(index <= loadedIndex, 'index is of a loaded ctc');
      //   const [ctc, newCtcArr] = getNftCtc(nftCtcs, index, maxIndex);
      //   const c = fromSome(ctc, thisContract);
      //   chkCtcValid(c);
      //   check(newCtcArr.length == nftCtcs.length);
      //   return () => [c, newCtcArr, rN];
      // };
      // const checkValidUsr = (user, rNum) => {
      // const rN = getRNum(rNum);
      // const userCtc = uMap[user];
      // check(typeOf(userCtc) !== null, 'user has inserted token');
      // const c = fromSome(userCtc, thisContract);
      // chkCtcValid(c);
      // return () => {
      //   check(typeOf(c) == Contract);
      //   return [c, rN];
      // };
      // };
    })
    .invariant(balance() === 0 && balance(payToken) / NFT_COST == toksTkn)
    .while(toksTkn < rows.length * NUM_OF_NFTS)
    .paySpec([payToken])
    .api(
      api.loadRow,
      (_, _) => {
        check(loadedRows < rows.length);
        const row = getRow(this);
        const sRow = fromSome(row, defRow);
        check(sRow.loadedIndex <= sRow.nftCtcs.length - 1);
        const isRowFull = sRow.loadedIndex == sRow.nftCtcs.length;
        check(!isRowFull);
      },
      (_, _) => handlePmt(0),
      (contract, rNum, notify) => {
        check(loadedRows < rows.length);
        const nR = getRNum(rNum);
        const row = getRow(this);
        const sRow = fromSome(row, defRow);
        const isRowFull = sRow.loadedIndex == sRow.nftCtcs.length;
        check(!isRowFull);
        check(sRow.loadedIndex < sRow.nftCtcs.length);
        const newArr = sRow.nftCtcs.set(
          sRow.loadedIndex,
          Maybe(Contract).Some(contract)
        );
        rowMap[this] = {
          nftCtcs: newArr,
          loadedIndex: sRow.loadedIndex + 1,
          rowToksTkn: 0,
        };
        notify([loadedRows, sRow.loadedIndex]);
        return [nR, toksTkn, rows, loadedRows];
      }
    )
    .api(
      api.checkIfLoaded,
      () => {
        check(isSome(rowMap[this]));
        check(loadedRows < rows.length);
      },
      () => handlePmt(0),
      notify => {
        check(loadedRows < rows.length);
        check(isSome(rowMap[this]));
        const row = getRow(this);
        const sRow = fromSome(row, defRow);
        const isRfull = sRow.loadedIndex == sRow.nftCtcs.length;
        const nLoaded = isRfull ? loadedRows + 1 : loadedRows;
        const k = isRfull ? true : false;
        const nRows = rows.set(loadedRows, Maybe(RowN).Some(this));
        notify(k);
        return [R, toksTkn, nRows, nLoaded];
      }
    )
    .api(
      api.insertToken,
      rNum => {
        const rN = getRNum(rNum);
        check(loadedRows == rows.length, 'has loaded rows');
        const rowIndex = rN % rows.length;
        const maxIndex = rows.length;
        check(rowIndex <= maxIndex, 'assume assigned row exists');
      },
      _ => handlePmt(NFT_COST),
      (rNum, notify) => {
        check(loadedRows == rows.length, 'has loaded rows');
        const rN = getRNum(rNum);
        const rowIndex = rN % rows.length;
        const maxIndex = rows.length - 1;
        check(rowIndex <= maxIndex, 'require assigned row exists');
        const r = getRKey(rowIndex);
        const d = {
          nftContract: Maybe(Contract).None(),
          row: Maybe(RowN).Some(r),
        };
        uMap[this] = d;
        notify(r);
        return [rN, toksTkn + 1, rows, loadedRows];
      }
    )
    .api(
      api.turnCrank,
      _ => {
        const u = uMap[this];
        check(typeOf(u) !== null);
        const user = fromSome(u, defUsr);
        const uR = user.row;
        check(isSome(uR) && isNone(user.nftContract), 'make sure user has row');
      },
      _ => handlePmt(0),
      (rNum, notify) => {
        const rN = getRNum(rNum);
        const u = uMap[this];
        check(typeOf(u) !== null);
        const user = fromSome(u, defUsr);
        const uR = user.row;
        check(isSome(uR) && isNone(user.nftContract), 'make sure user has row');
        switch (uR) {
          case Some: {
            const rData = rowMap[uR];
            const rowForUsr = fromSome(rData, defRow);
            const { nftCtcs, rowToksTkn, loadedIndex } = rowForUsr;
            const nftCtcIndex = rN % (nftCtcs.length - 1);
            const nonTakenLength = nftCtcs.length - rowToksTkn;
            check(nonTakenLength > 0, 'require machine has NFTs');
            const index = rN % nonTakenLength;
            const maxIndex = nonTakenLength - 1;
            check(index <= loadedIndex, 'index is of a loaded ctc');
            const [slot, newArr] = getNftCtc(nftCtcs, index, maxIndex);
            check(
              nftCtcIndex <= maxIndex,
              'require assigned nft contract exists in row'
            );
            check(isSome(slot), 'make sure nft is valid');
            uMap[this] = {
              row: user.row,
              nftContract: slot,
            };
            rowMap[uR] = {
              ...rowForUsr,
              nftCtcs: newArr,
            };
            notify(fromSome(slot, thisContract));
          }
          case None: {
            assert(true);
          }
        }
        return [R, toksTkn, rows, loadedRows];
      }
    )
    .api(
      api.finishTurnCrank,
      _ => {
        const user = fromSome(uMap[this], defUsr);
        check(isSome(user.nftContract));
        const nCtc = fromSome(user.nftContract, thisContract);
        check(nCtc !== thisContract);
      },
      _ => handlePmt(0),
      (rNum, notify) => {
        const user = fromSome(uMap[this], defUsr);
        check(isSome(user.nftContract));
        const nCtc = fromSome(user.nftContract, thisContract);
        check(nCtc !== thisContract);
        const rN = getRNum(rNum);
        const dispenserCtc = remote(nCtc, dispenserI);
        const nft = dispenserCtc.setOwner(this);
        delete uMap[this];
        notify(nft);
        return [rN, toksTkn, rows, loadedRows];
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
  const Dispenser = Participant('Dispenser', {
    ready: Fun([Contract], Null),
    nft: Token,
    mCtcAddr: Address,
  });
  const api = API(dispenserI);
  const v = View({
    nft: Token,
  });

  init();

  Dispenser.only(() => {
    const nft = declassify(interact.nft);
    const mCtcAddr = declassify(interact.mCtcAddr);
  });
  Dispenser.publish(nft, mCtcAddr);
  v.nft.set(nft);
  commit();
  Dispenser.pay([[1, nft]]);

  check(balance(nft) == 1);

  Dispenser.interact.ready(getContract());

  commit();

  const [[owner], k2] = call(api.setOwner).assume(_ => {
    check(this == mCtcAddr);
  });
  check(this == mCtcAddr);
  k2(nft);

  commit();

  const [[], k3] = call(api.getNft).assume(() => {
    check(this == owner);
  });
  check(this == owner);
  transfer(1, nft).to(this);
  check(balance(nft) == 0);
  k3(nft);

  commit();
});
