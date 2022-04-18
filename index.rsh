'reach 0.1';
'use strict';

// 437
const NUM_OF_NFTS = 3;
const NUM_OF_ROWS = 3;
const NFT_COST = 1;

const defNfts = Array.replicate(NUM_OF_NFTS, Maybe(Contract).None());

const RowN = Address;
const Row = Object({
  nftCtcs: Array(Maybe(Contract), NUM_OF_NFTS),
  loadedCtcs: UInt,
  rowToksTkn: UInt,
});
const defRow = {
  nftCtcs: defNfts,
  loadedCtcs: 0,
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
    createRow: Fun([], Address),
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

  const [R, toksTkn, rows, loadedRows, tokensLoaded, emptyRows, createdRows] =
    parallelReduce([digest(0), 0, rPicker, 0, 0, 0, 0])
      .define(() => {
        // TODO - Jay recommends XORing these before running the digest function.  But there are 3 types here (uint, int, digest) that don't support being XORed together.
        // const getRNum = (N) => digest(N^ R, thisConsensusTime(), thisConsensusSecs())

        // this would not compile when using thisConsensusTime() and thisConsensusSecs()
        // hence the "lastConsensus" things instead
        const getRNum = N =>
          digest(N, R, lastConsensusTime(), lastConsensusSecs());
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
          check(isSome(rowMap[user]), 'check row can be loaded');
          check(loadedRows <= rows.length);
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
          check(isSome(rowMap[user]), 'check row can be updated');
          rowMap[user] = {
            nftCtcs: newArr,
            loadedCtcs: r.loadedCtcs + 1,
            rowToksTkn: 0,
          };
          return () => r.loadedCtcs + 1;
        };
        const chkLoad = user => {
          check(isSome(rowMap[user]), 'check row exist');
          check(
            loadedRows < rows.length,
            'check loaded rows are less than length'
          );
          return () => {
            const row = getRow(user);
            const sRow = fromSome(row, defRow);
            const isRfull = sRow.loadedCtcs == sRow.nftCtcs.length;
            const nLoaded = isRfull ? loadedRows + 1 : loadedRows;
            const nRows = rows.set(loadedRows, Maybe(RowN).Some(user));
            return [nLoaded, nRows, isRfull];
          };
        };
        const chkValidRow = rNum => {
          const rN = getRNum(rNum);
          check(loadedRows <= rows.length, 'has loaded rows');
          const nonTakenLngth = loadedRows - emptyRows;
          const rowIndex = rN % nonTakenLngth;
          const maxIndex = nonTakenLngth;
          check(
            rowIndex >= 0 && rowIndex <= maxIndex,
            'row array bounds check'
          );
          const [row, _] = getIfrmArr(rows, rowIndex, maxIndex, Address);
          // const row = rows[1]
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
              const pRow = rowMap[row];
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
        const chckValidCtc = (usr, rNum) => {
          const u = uMap[usr];
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
                const rData = rowMap[uR];
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
                check(index >= 0 && index <= maxIndex, 'index is of a loaded ctc');
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
      })
      .invariant(
        balance() === 0 &&
          balance(payToken) / NFT_COST == toksTkn &&
          rowMap.size() == createdRows
      )
      .while(emptyRows < rows.length)
      .paySpec([payToken])
      .api(
        api.createRow,
        () => {
          check(createdRows < rows.length);
          check(isNone(rows[createdRows]), 'check row exist 1');
          check(isNone(rowMap[this]), 'check row exist 2');
        },
        () => handlePmt(0),
        notify => {
          check(createdRows < rows.length);
          check(isNone(rows[createdRows]), 'check row exist');
          check(isNone(rowMap[this]), 'check row exist');
          const nRows = rows.set(createdRows, Maybe(Address).Some(this));
          check(isSome(nRows[createdRows]), 'check row was created');
          rowMap[this] = defRow;
          check(isSome(rowMap[this]), 'check row created');
          notify(this);
          return [
            R,
            toksTkn,
            nRows,
            loadedRows,
            tokensLoaded,
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
            toksTkn,
            rows,
            loadedRows,
            tokensLoaded + nToksLoaded,
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
            toksTkn,
            nRows,
            nLoaded,
            tokensLoaded,
            emptyRows,
            createdRows,
          ];
        }
      )
      .api(
        api.insertToken,
        rNum => {
          const _ = chkValidRow(rNum);
        },
        _ => handlePmt(NFT_COST),
        (rNum, notify) => {
          const [rD, row, rN] = chkValidRow(rNum);
          uMap[this] = rD;
          notify(row);
          return [
            rN,
            toksTkn + 1,
            rows,
            loadedRows,
            tokensLoaded,
            emptyRows,
            createdRows,
          ];
        }
      )
      .api(
        api.turnCrank,
        rNum => {
          const _ = chckValidCtc(this, rNum)();
        },
        _ => handlePmt(0),
        (rNum, notify) => {
          const rN = getRNum(rNum);
          const [user, slot, newArr, uR, rowForUsr, eRows] = chckValidCtc(
            this,
            rNum
          )();
          check(isSome(rowMap[uR]), 'row exist');
          check(isSome(uMap[this]), 'user exist');
          uMap[this] = {
            row: user.row,
            nftContract: Maybe(Contract).Some(slot),
          };
          rowMap[uR] = {
            ...rowForUsr,
            nftCtcs: newArr,
            rowToksTkn: rowForUsr.rowToksTkn + 1,
          };
          notify(slot);
          return [
            rN,
            toksTkn,
            rows,
            loadedRows,
            tokensLoaded,
            eRows,
            createdRows,
          ];
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
          return [
            rN,
            toksTkn,
            rows,
            loadedRows,
            tokensLoaded,
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
