'reach 0.1';
'use strict';

// 437
const NUM_OF_NFTS = 3;
const NUM_OF_ROWS = 3;
const NFT_COST = 1;

// dispenser interface to be shared across both contracts
const dispenserI = {
  setOwner: Fun([Address], Token),
  getNft: Fun([], Token),
};

// alias for row item
const RowN = Address;

export const machine = Reach.App(() => {
  setOptions({ connectors: [ALGO] });

  const Machine = Participant('Machine', {
    payToken: Token,
    ready: Fun([Contract], Null),
  });
  const api = API({
    createRow: Fun([], Tuple(Address, UInt)),
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

  const Users = new Map(
    Object({
      nftContract: Maybe(Contract),
      row: Maybe(RowN),
    })
  );
  const defUsr = {
    nftContract: Maybe(Contract).None(),
    row: Maybe(RowN).None(),
  };

  const Row = Object({
    nftCtcs: Array(Maybe(Contract), NUM_OF_NFTS),
    loadedCtcs: UInt,
    rowToksTkn: UInt,
  });
  const Rows = new Map(Row);
  const defNfts = Array.replicate(NUM_OF_NFTS, Maybe(Contract).None());
  const defRow = {
    nftCtcs: defNfts,
    loadedCtcs: 0,
    rowToksTkn: 0,
  };

  const rowPicker = Array.replicate(NUM_OF_ROWS, Maybe(Address).None());

  const thisContract = getContract();

  const handlePmt = amt => [0, [amt, payToken]];

  const getRow = row => Rows[row];

  Machine.interact.ready(thisContract);

  const [R, totToksTkn, rowArr, loadedRows, totToksLoaded, emptyRows, createdRows] =
    parallelReduce([digest(0), 0, rowPicker, 0, 0, 0, 0])
      .define(() => {
        // TODO - Jay recommends XORing these before running the digest function.  But there are 3 types here (uint, int, digest) that don't support being XORed together.
        // const getRNum = (N) => digest(N^ R, thisConsensusTime(), thisConsensusSecs())

        // this would not compile when using thisConsensusTime() and thisConsensusSecs()
        // hence the "lastConsensus" things instead
        const getRNum = N =>
          digest(N, R, lastConsensusTime(), lastConsensusSecs());
        const chkRowCreate = user => {
          check(createdRows < rowArr.length, 'too many rows');
          check(isNone(rowArr[createdRows]), 'check row exist');
          check(isNone(Rows[user]), 'check row exist');
          const nRows = rowArr.set(createdRows, Maybe(Address).Some(user));
          check(isSome(nRows[createdRows]), 'check row was created');
          return nRows;
        };
        const getIfrmArr = (arr, i, sz, t) => {
          const k = sz == 0 ? 0 : sz - 1;
          const ip = i % sz;
          const item = arr[ip];
          check(isSome(item), 'arr item has data');
          const defI = Maybe(t).None();
          const newArr = Array.set(arr, ip, arr[k]);
          const nullEndArr = Array.set(newArr, k, defI);
          return [item, nullEndArr];
        };
        const chkRow = user => {
          check(isSome(Rows[user]), 'check row can be loaded');
          check(loadedRows <= rowArr.length);
          const row = getRow(user);
          const sRow = fromSome(row, defRow);
          check(sRow.loadedCtcs < sRow.nftCtcs.length);
          const isRowFull = sRow.loadedCtcs == sRow.nftCtcs.length;
          check(!isRowFull);
          return () => sRow;
        };
        const updtRow = (user, r, ctc) => {
          const newArr = r.nftCtcs.set(r.loadedCtcs, Maybe(Contract).Some(ctc));
          check(
            r.loadedCtcs + 1 <= newArr.length,
            'make sure row does not exceed bounds'
          );
          check(isSome(Rows[user]), 'check row can be updated');
          Rows[user] = {
            nftCtcs: newArr,
            loadedCtcs: r.loadedCtcs + 1,
            rowToksTkn: 0,
          };
          return () => r.loadedCtcs + 1;
        };
        const chkLoad = user => {
          check(isSome(Rows[user]), 'check row exist');
          check(
            loadedRows < rowArr.length,
            'check loaded rowArr are less than length'
          );
          return () => {
            const row = getRow(user);
            const sRow = fromSome(row, defRow);
            const isRfull = sRow.loadedCtcs == sRow.nftCtcs.length;
            const nLoaded = isRfull ? loadedRows + 1 : loadedRows;
            const nRows = rowArr.set(loadedRows, Maybe(RowN).Some(user));
            return [nLoaded, nRows, isRfull];
          };
        };
        const chkInsertTkn = rNum => {
          const rN = getRNum(rNum);
          check(loadedRows <= rowArr.length, 'has loaded rowArr');
          const nonTakenLngth = loadedRows - emptyRows;
          const rowIndex = rN % nonTakenLngth;
          const maxIndex = nonTakenLngth;
          check(
            rowIndex >= 0 && rowIndex <= maxIndex,
            'row array bounds check'
          );
          const [row, _] = getIfrmArr(rowArr, rowIndex, maxIndex, Address);
          // const row = rowArr[1];
          check(isSome(row), 'check row exist');
          switch (row) {
            case None:
              assert(true);
              const d = {
                nftContract: Maybe(Contract).None(),
                row: Maybe(RowN).None(),
              };
              return [d, Machine, rN];
            case Some: {
              const pRow = Rows[row];
              check(typeOf(pRow) !== null, 'check row contents exists');
              check(isSome(pRow), 'row is valid');
              const pR = fromSome(pRow, defRow);
              check(
                pR.rowToksTkn < pR.nftCtcs.length,
                'all tokens are taken from row'
              );
              const d = {
                nftContract: Maybe(Contract).None(),
                row: Maybe(RowN).Some(row),
              };
              return [d, row, rN];
            }
          }
        };
        const chkTurnCrank = (usr, rNum) => {
          const u = Users[usr];
          check(typeOf(u) !== null, 'user has not inserted token');
          check(isSome(u), 'there is uer data');
          const user = fromSome(u, defUsr);
          const uR = user.row;
          check(
            isSome(uR) && isNone(user.nftContract),
            'make sure user has row'
          );
          return () => {
            switch (uR) {
              case Some: {
                const rData = Rows[uR];
                check(isSome(rData), 'check row is valid');
                const rowForUsr = fromSome(rData, defRow);
                const { nftCtcs, rowToksTkn, loadedCtcs } = rowForUsr;
                check(
                  loadedCtcs <= nftCtcs.length,
                  'loaded nfts are in bounds'
                );
                const rN = getRNum(rNum);
                check(rowToksTkn < nftCtcs.length, 'nfts taken are in bounds');
                const nonTakenLength = loadedCtcs - rowToksTkn;
                const index = rN % nonTakenLength;
                const maxIndex = nonTakenLength;
                check(
                  index >= 0 && index <= maxIndex,
                  'index is of a loaded ctc'
                );
                const [slot, newArr] = getIfrmArr(
                  nftCtcs,
                  index,
                  maxIndex,
                  Contract
                );
                check(isSome(slot), 'make sure nft is valid');
                const sSlot = fromSome(slot, thisContract);
                const eRows =
                  rowToksTkn + 1 == nftCtcs.length ? emptyRows + 1 : emptyRows;
                return [user, sSlot, newArr, uR, rowForUsr, eRows];
              }
              case None: {
                assert(true);
                return [
                  user,
                  thisContract,
                  defNfts,
                  Machine,
                  defRow,
                  emptyRows,
                ];
              }
            }
          };
        };
        const chkFinalCrank = u => {
          const user = fromSome(Users[u], defUsr);
          check(isSome(user.nftContract));
          const nCtc = fromSome(user.nftContract, thisContract);
          check(nCtc !== thisContract);
          return nCtc;
        };
      })
      .invariant(
        balance() === 0 &&
          balance(payToken) / NFT_COST == totToksTkn &&
          Rows.size() == createdRows
      )
      .while(emptyRows < rowArr.length)
      .paySpec([payToken])
      .api(
        api.createRow,
        () => {
          const _ = chkRowCreate(this);
        },
        () => handlePmt(0),
        notify => {
          const nRows = chkRowCreate(this);
          Rows[this] = defRow;
          check(isSome(Rows[this]), 'check row created');
          notify([this, createdRows + 1]);
          return [
            R,
            totToksTkn,
            nRows,
            loadedRows,
            totToksLoaded,
            emptyRows,
            createdRows + 1,
          ];
        }
      )
      .api(
        api.loadRow,
        (_, _) => {
          const _ = chkRow(this)();
        },
        (_, _) => handlePmt(0),
        (contract, rNum, notify) => {
          const nR = getRNum(rNum);
          const r = chkRow(this)();
          const nToksLoaded = updtRow(this, r, contract)();
          notify([loadedRows + 1, r.loadedCtcs + 1]);
          return [
            nR,
            totToksTkn,
            rowArr,
            loadedRows,
            totToksLoaded + nToksLoaded,
            emptyRows,
            createdRows,
          ];
        }
      )
      .api(
        api.checkIfLoaded,
        () => {
          const _ = chkLoad(this)();
        },
        () => handlePmt(0),
        notify => {
          const [nLoaded, nRows, isRfull] = chkLoad(this)();
          notify(isRfull);
          return [
            R,
            totToksTkn,
            nRows,
            nLoaded,
            totToksLoaded,
            emptyRows,
            createdRows,
          ];
        }
      )
      .api(
        api.insertToken,
        rNum => {
          const _ = chkInsertTkn(rNum);
        },
        _ => handlePmt(NFT_COST),
        (rNum, notify) => {
          const [rD, row, rN] = chkInsertTkn(rNum);
          Users[this] = rD;
          notify(row);
          return [
            rN,
            totToksTkn + 1,
            rowArr,
            loadedRows,
            totToksLoaded,
            emptyRows,
            createdRows,
          ];
        }
      )
      .api(
        api.turnCrank,
        rNum => {
          const _ = chkTurnCrank(this, rNum)();
        },
        _ => handlePmt(0),
        (rNum, notify) => {
          const rN = getRNum(rNum);
          const [user, slot, newArr, uR, rowForUsr, eRows] = chkTurnCrank(
            this,
            rNum
          )();
          Users[this] = {
            row: user.row,
            nftContract: Maybe(Contract).Some(slot),
          };
          Rows[uR] = {
            ...rowForUsr,
            nftCtcs: newArr,
            rowToksTkn: rowForUsr.rowToksTkn + 1,
          };
          notify(slot);
          return [
            rN,
            totToksTkn,
            rowArr,
            loadedRows,
            totToksLoaded,
            eRows,
            createdRows,
          ];
        }
      )
      .api(
        api.finishTurnCrank,
        _ => {
          const _ = chkFinalCrank(this);
        },
        _ => handlePmt(0),
        (rNum, notify) => {
          const ctc = chkFinalCrank(this);
          const rN = getRNum(rNum);
          const dispenserCtc = remote(ctc, dispenserI);
          const nft = dispenserCtc.setOwner(this);
          delete Users[this];
          notify(nft);
          return [
            rN,
            totToksTkn,
            rowArr,
            loadedRows,
            totToksLoaded,
            emptyRows,
            createdRows,
          ];
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

  const [[owner], k1] = call(api.setOwner).assume(_ => {
    check(this == mCtcAddr);
  });
  check(this == mCtcAddr);
  k1(nft);

  commit();

  const [[], k2] = call(api.getNft).assume(() => {
    check(this == owner);
  });
  check(this == owner);
  transfer(1, nft).to(this);
  k2(nft);

  commit();
});
