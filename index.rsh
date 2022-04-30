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

export const machine = Reach.App(() => {
  setOptions({ connectors: [ALGO] });

  const Row = Object({
    slots: Array(Maybe(Contract), NUM_OF_ROW_ITEMS),
    loadedCtcs: UInt,
    rowToksTkn: UInt,
  });

  const User = Object({
    step: UInt,
    nftContract: Maybe(Contract),
    row: Maybe(Address),
  });

  const Machine = Participant('Machine', {
    payToken: Token,
    numOfRows: UInt,
    numOfSlots: UInt,
    ready: Fun([Contract], Null),
  });
  const api = API({
    createRow: Fun([], Tuple(Address, UInt)),
    loadRow: Fun([Contract, UInt], Tuple(UInt, UInt)),
    insertToken: Fun([UInt], Address),
    turnCrank: Fun([UInt], Contract),
    finishTurnCrank: Fun([UInt], Contract),
  });
  const view = View({
    numOfRows: UInt,
    numOfSlots: UInt,
    loadedRows: UInt,
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
  const defUser = {
    step: 0,
    nftContract: Maybe(Contract).None(),
    row: Maybe(Address).None(),
  };
  const Rows = new Map(Row);
  const defNfts = Array.replicate(NUM_OF_ROW_ITEMS, Maybe(Contract).None());
  const defRow = {
    slots: defNfts,
    loadedCtcs: 0,
    rowToksTkn: 0,
  };

  const rowPicker = Array.replicate(NUM_OF_ROWS, Maybe(Address).None());
  const thisContract = getContract();

  const handlePmt = amt => [0, [amt, payToken]];
  const getRow = row => Rows[row];
  const getUserRow = user => {
    const sRow = fromSome(user.row, Machine);
    const assignedRow = Rows[sRow];
    const rowData = fromSome(assignedRow, defRow);
    return [rowData, sRow];
  };

  // set views
  view.payToken.set(payToken);
  view.numOfRows.set(NUM_OF_ROWS);
  view.numOfSlots.set(NUM_OF_ROW_ITEMS);
  view.nftCost.set(NFT_COST);
  view.getUser.set(u => fromSome(Users[u], defUser));
  view.getRow.set(u => fromSome(Rows[u], defRow));

  Machine.interact.ready(thisContract);

  const [R, totToksTkn, rowArr, loadedRows, emptyRows, createdRows, keepGoing] =
    parallelReduce([digest(0), 0, rowPicker, 0, 0, 0, true])
      .define(() => {
        view.loadedRows.set(loadedRows);
        view.emptyRows.set(emptyRows);
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
        const chkRowCreate = user => {
          check(createdRows < rowArr.length, 'too many rows');
          check(isNone(rowArr[createdRows]), 'check row exist');
          check(isNone(Rows[user]), 'check row exist');
          const nRows = rowArr.set(createdRows, Maybe(Address).Some(user));
          return () => {
            Rows[user] = defRow;
            return nRows;
          };
        };
        const loadIntoRow = (r, ctc) => {
          check(isSome(Rows[r]), 'check row can be loaded');
          check(loadedRows <= rowArr.length);
          const row = getRow(r);
          const sRow = fromSome(row, defRow);
          check(sRow.loadedCtcs < sRow.slots.length);
          const isRowFull = sRow.loadedCtcs == sRow.slots.length;
          check(!isRowFull);
          const newLoadedCount = sRow.loadedCtcs + 1;
          const newArr = sRow.slots.set(
            sRow.loadedCtcs,
            Maybe(Contract).Some(ctc)
          );
          check(
            newLoadedCount <= newArr.length,
            'make sure row does not exceed bounds'
          );
          return () => {
            Rows[r] = {
              slots: newArr,
              loadedCtcs: newLoadedCount,
              rowToksTkn: 0,
            };
            return newLoadedCount;
          };
        };
        const insertPayTok = (user, rNum) => {
          const rN = getRNum(rNum);
          check(isNone(Users[user]), 'user has inserted token');
          check(loadedRows > 0, 'at least one row loaded');
          check(loadedRows > emptyRows, 'all rows are empty');
          check(loadedRows <= rowArr.length, 'has loaded rowArr');
          const nonTakenLngth = loadedRows - emptyRows;
          const rowIndex = rN % nonTakenLngth;
          const maxIndex = nonTakenLngth;
          check(rowIndex <= maxIndex, 'row array bounds check');
          const [row, nArr] = getIfrmArr(rowArr, rowIndex, maxIndex, Address);
          const sRow = fromSome(row, Machine);
          return () => {
            Users[user] = {
              ...defUser,
              row: row,
            };
            const rowData = fromSome(Rows[sRow], defRow);
            const newRowArr =
              rowData.rowToksTkn + 1 == rowData.slots.length ? nArr : rowArr;
            return [fromSome(row, Machine), newRowArr, rN];
          };
        };
        const initTurnCrank = (usr, rNum) => {
          const rN = getRNum(rNum);
          const u = Users[usr];
          const user = fromSome(u, defUser);
          const uRowI = user.row;
          check(typeOf(u) !== null, 'user has not inserted token');
          check(isSome(uRowI), 'make sure user has row');
          check(isNone(user.nftContract), 'user is not assigned nft')
          const [rowData, rowKey] = getUserRow(user);
          const { rowToksTkn, slots, loadedCtcs } = rowData;
          const isRowEmpty = rowToksTkn == loadedCtcs;
          check(!isRowEmpty, 'row is empty');
          check(loadedCtcs == slots.length);
          check(rowToksTkn < slots.length, 'row tokens taken are in bounds');
          const nonTakenLength = slots.length - rowToksTkn;
          const slotIndex = rN % nonTakenLength;
          const maxIndex = nonTakenLength;
          check(slotIndex <= maxIndex, 'slot index not in bounds');
          const [slot, nSlots] = getIfrmArr(
            slots,
            slotIndex,
            maxIndex,
            Contract
          );
          return () => {
            Users[usr] = {
              ...user,
              nftContract: slot,
            };
            Rows[rowKey] = {
              ...rowData,
              slots: nSlots,
              rowToksTkn: rowToksTkn + 1,
            };
            return [
              fromSome(slot, thisContract),
              rowToksTkn + 1 == slots.length ? emptyRows + 1 : emptyRows,
              rN,
            ];
          };
        };
        const endTurnCrank = (u, rNum) => {
          const rN = getRNum(rNum);
          const user = Users[u];
          check(isSome(user), 'user exist');
          const sUser = fromSome(user, defUser);
          check(isSome(sUser.nftContract), 'contract is set');
          const ctc = fromSome(sUser.nftContract, thisContract);
          return () => {
            const dispenserCtc = remote(ctc, dispenserI);
            const nft = dispenserCtc.setOwner(u);
            check(typeOf(nft) !== null);
            delete Users[u];
            return [ctc, rN];
          };
        };
      })
      .invariant(
        balance() === 0 &&
          NFT_COST * totToksTkn == balance(payToken) &&
          Rows.size() == createdRows
      )
      .while(keepGoing)
      .paySpec([payToken])
      .api(
        api.createRow,
        () => {
          const _ = chkRowCreate(this);
        },
        () => handlePmt(0),
        notify => {
          const nRows = chkRowCreate(this)();
          notify([this, createdRows + 1]);
          return [
            R,
            totToksTkn,
            nRows,
            loadedRows,
            emptyRows,
            createdRows + 1,
            true,
          ];
        }
      )
      .api(
        api.loadRow,
        (contract, _) => {
          const _ = loadIntoRow(this, contract);
        },
        (_, _) => handlePmt(0),
        (contract, rNum, notify) => {
          const rN = getRNum(rNum);
          const newRowLoadCount = loadIntoRow(this, contract)();
          notify([loadedRows + 1, newRowLoadCount]);
          return [
            rN,
            totToksTkn,
            rowArr,
            newRowLoadCount == NUM_OF_ROW_ITEMS ? loadedRows + 1 : loadedRows,
            emptyRows,
            createdRows,
            true,
          ];
        }
      )
      .api(
        api.insertToken,
        rNum => {
          const _ = insertPayTok(this, rNum);
        },
        _ => handlePmt(NFT_COST),
        (rNum, notify) => {
          const [assignedRow, nArr, rN] = insertPayTok(this, rNum)();
          notify(assignedRow);
          return [
            rN,
            totToksTkn + 1,
            nArr,
            loadedRows,
            emptyRows,
            createdRows,
            true,
          ];
        }
      )
      .api(
        api.turnCrank,
        rNum => {
          const _ = initTurnCrank(this, rNum);
        },
        _ => handlePmt(0),
        (rNum, notify) => {
          const [rowForUsr, eRows, rN] = initTurnCrank(this, rNum)();
          notify(rowForUsr);
          return [rN, totToksTkn, rowArr, loadedRows, eRows, createdRows, true];
        }
      )
      .api(
        api.finishTurnCrank,
        rNum => {
          const _ = endTurnCrank(this, rNum);
        },
        _ => handlePmt(0),
        (rNum, notify) => {
          const [ctc, rN] = endTurnCrank(this, rNum)();
          notify(ctc);
          return [
            rN,
            totToksTkn,
            rowArr,
            loadedRows,
            emptyRows,
            createdRows,
            true,
          ];
        }
      );

  transfer(balance()).to(Machine);
  transfer(balance(payToken), payToken).to(Machine);
  commit();

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
