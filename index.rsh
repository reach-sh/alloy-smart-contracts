'reach 0.1';
'use strict';

const NFT_COST = 1;
const NUM_OF_ROWS = 3;
const NUM_OF_ROW_ITEMS = 3;

// dispenser interface to be shared across both contracts
const dispenserI = {
  setOwner: Fun([Address], Token),
  getNft: Fun([], Token),
};

// alias for row item
const RowN = Address;

export const machine = Reach.App(() => {
  setOptions({ connectors: [ALGO] });

  const Row = Object({
    nftCtcs: Array(Maybe(Contract), NUM_OF_ROW_ITEMS),
    loadedCtcs: UInt,
    rowToksTkn: UInt,
  });

  const User = Object({
    nftContract: Maybe(Contract),
    rowIndex: Maybe(UInt),
    row: Maybe(RowN),
  });

  const Machine = Participant('Machine', {
    payToken: Token,
    ready: Fun([Contract], Null),
  });
  const api = API({
    createRow: Fun([], Tuple(Address, UInt)),
    loadRow: Fun([Contract, UInt], Tuple(UInt, UInt)),
    checkIfLoaded: Fun([], Bool),
    insertToken: Fun([UInt], UInt),
    turnCrank: Fun([UInt], RowN),
    finishTurnCrank: Fun([UInt], Contract),
    setOwner: Fun([], Null),
  });
  const view = View({
    numOfRows: UInt,
    numOfSlots: UInt,
    loadedRows: UInt,
    totalToksTaken: UInt,
    totalToksLoaded: UInt,
    createdRows: UInt,
    emptyRows: UInt,
    payToken: Token,
    nftCost: UInt,
    getUser: Fun([Address], User),
    getRow: Fun([Address], Row),
  });
  init();

  Machine.only(() => {
    const payToken = declassify(interact.payToken);
  });
  Machine.publish(payToken);

  const Users = new Map(User);
  const defUsr = {
    nftContract: Maybe(Contract).None(),
    rowIndex: Maybe(UInt).None(),
    row: Maybe(RowN).None(),
  };
  const Rows = new Map(Row);
  const defNfts = Array.replicate(NUM_OF_ROW_ITEMS, Maybe(Contract).None());
  const defRow = {
    nftCtcs: defNfts,
    loadedCtcs: 0,
    rowToksTkn: 0,
  };

  const rowPicker = Array.replicate(NUM_OF_ROWS, Maybe(Address).None());

  const thisContract = getContract();

  const handlePmt = amt => [0, [amt, payToken]];

  const getRow = row => Rows[row];

  // set views
  view.payToken.set(payToken);
  view.numOfRows.set(NUM_OF_ROWS);
  view.numOfSlots.set(NUM_OF_ROW_ITEMS);
  view.nftCost.set(NFT_COST);
  view.getUser.set(u => fromSome(Users[u], defUsr));
  view.getRow.set(u => fromSome(Rows[u], defRow));

  Machine.interact.ready(thisContract);

  const [
    R,
    totToksTkn,
    rowArr,
    loadedRows,
    totToksLoaded,
    emptyRows,
    createdRows,
  ] = parallelReduce([digest(0), 0, rowPicker, 0, 0, 0, 0])
    .define(() => {
      view.loadedRows.set(loadedRows);
      view.totalToksTaken.set(totToksTkn);
      view.totalToksLoaded.set(totToksLoaded);
      view.createdRows.set(createdRows);
      view.emptyRows.set(emptyRows);
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
      const getIfrmArr = (arr, i, sz, t, y) => {
        const k = sz == 0 ? 0 : sz - 1;
        const ip = y ? i : i % sz;
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
          check(nLoaded <= rowArr.length, 'max rows reached');
          const nRows = rowArr.set(loadedRows, Maybe(RowN).Some(user));
          return [nLoaded, nRows, isRfull];
        };
      };
      const chkInsertTkn = (rNum, user) => {
        const rN = getRNum(rNum);
        check(isNone(Users[user]), 'user has inserted token');
        check(loadedRows > 0, 'at least one row loaded');
        check(loadedRows > emptyRows, 'all rows are empty')
        check(loadedRows <= rowArr.length, 'has loaded rowArr');
        const nonTakenLngth = loadedRows - emptyRows;
        const rowIndex = rN % nonTakenLngth;
        const maxIndex = nonTakenLngth - 1;
        check(rowIndex <= maxIndex, 'row array bounds check');
        const d = {
          ...defUsr,
          rowIndex: Maybe(UInt).Some(rowIndex),
        };
        return [d, rN];
      };
      const chkTurnCrank = (usr, _) => {
        const u = Users[usr];
        check(typeOf(u) !== null, 'user has not inserted token');
        check(isSome(u), 'there is uer data');
        const user = fromSome(u, defUsr);
        const uRowI = user.rowIndex;
        check(
          isSome(uRowI) && isNone(user.nftContract),
          'make sure user has row'
        );
        const sRowI = fromSome(uRowI, 999);
        check(loadedRows <= rowArr.length, 'loaded rows out of bounds');
        check(sRowI !== 999, 'row is not valid');
        const nonEmptyLength = loadedRows - emptyRows;
        const maxIndex = nonEmptyLength;
        check(sRowI <= maxIndex, 'row array bounds check');
        const [row, nArr] = getIfrmArr(rowArr, sRowI, maxIndex, Address, false);
        check(isSome(row), 'row has data');
        return () => {
          switch (row) {
            case Some: {
              const rData = Rows[row];
              check(isSome(rData), 'check row is valid');
              const rowForUsr = fromSome(rData, defRow);
              const { nftCtcs, rowToksTkn, loadedCtcs } = rowForUsr;
              const isRowEmpty = rowToksTkn == nftCtcs.length;
              check(!isRowEmpty, 'row is empty');
              check(loadedCtcs <= nftCtcs.length, 'loaded nfts are in bounds');
              return [
                user,
                row,
                { ...rowForUsr, rowToksTkn: rowToksTkn },
                rowToksTkn + 1 == nftCtcs.length ? nArr : rowArr,
                rowToksTkn + 1 == nftCtcs.length ? emptyRows + 1 : emptyRows,
              ];
            }
            case None: {
              return [user, Machine, defRow, rowArr, emptyRows];
            }
          }
        };
      };
      const chkFinalCrank = (u, rNum) => {
        const user = fromSome(Users[u], defUsr);
        check(isSome(user.row), 'user is assigned row');
        check(isSome(user.rowIndex), 'user is assigned row index');
        check(isNone(user.nftContract), 'user does not have contract');
        check(emptyRows <= rowArr.length, 'empty rows in bounds');
        const rowData = Rows[fromSome(user.row, Machine)];
        check(fromSome(user.rowIndex, 999) < rowArr.length);
        check(isSome(rowData), 'row has data');
        const sRowData = fromSome(rowData, defRow);
        const { rowToksTkn, nftCtcs } = sRowData;
        const rN = getRNum(rNum);
        check(loadedRows <= rowArr.length, 'has loaded rows');
        check(rowToksTkn <= nftCtcs.length, 'row tokens taken are in bounds');
        const nonTakenLength = nftCtcs.length - rowToksTkn;
        const slotIndex = rN % nonTakenLength;
        const maxIndex = nonTakenLength;
        check(slotIndex <= maxIndex, 'slot index not in bounds');
        const [slot, nArr] = getIfrmArr(
          nftCtcs,
          slotIndex,
          maxIndex,
          Contract,
          false
        );
        const nCtc = fromSome(slot, thisContract);
        check(nCtc !== thisContract, 'slot contract is valid');
        return [
          user,
          nCtc,
          { ...sRowData, nftCtcs: nArr, rowToksTkn: rowToksTkn + 1 },
          emptyRows,
        ];
      };
    })
    .invariant(
      balance() === 0 &&
        balance(payToken) / NFT_COST == totToksTkn &&
        Rows.size() == createdRows
    )
    .while(totToksTkn <= NUM_OF_ROWS * NUM_OF_ROW_ITEMS)
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
        const _ = updtRow(this, r, contract)();
        notify([loadedRows + 1, r.loadedCtcs + 1]);
        return [
          nR,
          totToksTkn,
          rowArr,
          loadedRows,
          totToksLoaded + 1,
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
        const _ = chkInsertTkn(rNum, this);
      },
      _ => handlePmt(NFT_COST),
      (rNum, notify) => {
        const [rD, rN] = chkInsertTkn(rNum, this);
        Users[this] = rD;
        notify(fromSome(rD.rowIndex, 999));
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
        const [user, rowForUsr, rData, nRows, eRows] = chkTurnCrank(
          this,
          rNum
        )();
        Users[this] = {
          ...user,
          row: Maybe(RowN).Some(rowForUsr),
        };
        Rows[rowForUsr] = {
          ...rData,
        };
        notify(rowForUsr);
        return [
          rN,
          totToksTkn,
          nRows,
          loadedRows,
          totToksLoaded,
          eRows,
          createdRows,
        ];
      }
    )
    .api(
      api.finishTurnCrank,
      rNum => {
        const _ = chkFinalCrank(this, rNum);
      },
      _ => handlePmt(0),
      (rNum, notify) => {
        const [user, ctc, rData, eRows] = chkFinalCrank(this, rNum);
        Users[this] = {
          ...user,
          nftContract: Maybe(Contract).Some(ctc),
        };
        const t = fromSome(user.row, Machine);
        Rows[t] = rData;
        notify(ctc);
        return [
          R,
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
      api.setOwner,
      () => {},
      () => handlePmt(0),
      k => {
        const user = Users[this];
        const sUser = fromSome(user, defUsr);
        const ctc = fromSome(sUser.nftContract, thisContract);
        const dispenserCtc = remote(ctc, dispenserI);
        const nft = dispenserCtc.setOwner(this);
        check(typeOf(nft) !== null);
        delete Users[this];
        k(null);
        return [
          R,
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
    owner: Address,
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
  v.owner.set(owner);
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
