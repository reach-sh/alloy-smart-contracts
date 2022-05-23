'reach 0.1';
'use strict';

const NFT_COST = 1;
const NUM_OF_ROWS = 5;
const NUM_OF_ROW_ITEMS = 12;

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
    lastCompletedStep: UInt,
    nftContract: Maybe(Contract),
    row: Maybe(Address),
    rowIndex: Maybe(UInt),
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
    reset: Fun([UInt], Null),
  });
  const view = View({
    numOfRows: UInt,
    numOfSlots: UInt,
    loadedRows: UInt,
    emptyRows: UInt,
    payToken: Token,
    nftCost: UInt,
    totToksTkn: UInt,
    getUser: Fun([Address], User),
    getRow: Fun([Address], Row),
    getUserCtc: Fun([Address], Maybe(Contract)),
  });
  init();

  Machine.only(() => {
    const payToken = declassify(interact.payToken);
  });
  Machine.publish(payToken);

  // will store contracts for users that happen to 'quit' the flow before actually getting their NFT
  const UsersCtcs = new Map(Contract);

  const Users = new Map(User);
  const defUser = {
    lastCompletedStep: 0,
    nftContract: Maybe(Contract).None(),
    row: Maybe(Address).None(),
    rowIndex: Maybe(UInt).None(),
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
  view.getUserCtc.set(u => UsersCtcs[u]);

  Machine.interact.ready(thisContract);

  const [R, totToksTkn, rowArr, loadedRows, emptyRows, createdRows, keepGoing] =
    parallelReduce([digest(0), 0, rowPicker, 0, 0, 0, true])
      .define(() => {
        view.totToksTkn.set(totToksTkn);
        view.loadedRows.set(loadedRows);
        view.emptyRows.set(emptyRows);
        const defState = () => [
          R,
          totToksTkn,
          rowArr,
          loadedRows,
          emptyRows,
          createdRows,
          keepGoing,
        ];
        const getRNum = rNum => {
          const n = digest(rNum, thisConsensusTime(), thisConsensusSecs());
          return R ^ n;
        };
        const chkRows = () => {
          check(loadedRows > 0, 'at least one row loaded');
          check(loadedRows > emptyRows, 'all rows are empty');
          check(loadedRows <= rowArr.length, 'has loaded rowArr');
        };
        const getIfrmArr = (arr, i, sz, t) => {
          const defI = Maybe(t).None();
          const k = sz == 0 ? 0 : sz - 1;
          const ip = i % sz;
          const item = arr[ip];
          const newArr = Array.set(arr, ip, arr[k]);
          const nullEndArr = Array.set(newArr, k, defI);
          return [item, nullEndArr];
        };
        const createRow = user => {
          check(createdRows < rowArr.length, 'too many rows');
          check(isNone(rowArr[createdRows]), 'check row exist');
          check(isNone(Rows[user]), 'check row exist');
          const nRows = rowArr.set(createdRows, Maybe(Address).Some(user));
          return () => {
            Rows[user] = defRow;
            return nRows;
          };
        };
        const loadRow = (r, ctc) => {
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
        const insertToken = (user, rNum) => {
          const rN = getRNum(rNum);
          check(isNone(Users[user]), 'user has inserted token');
          chkRows();
          const nonTakenLngth = loadedRows - emptyRows;
          const rowIndex = rN % nonTakenLngth;
          const maxIndex = nonTakenLngth;
          check(rowIndex <= maxIndex, 'row array bounds check');
          const [row, _] = getIfrmArr(rowArr, rowIndex, maxIndex, Address);
          return () => {
            delete UsersCtcs[user];
            Users[user] = {
              ...defUser,
              lastCompletedStep: 1,
              rowIndex: Maybe(UInt).Some(rowIndex),
              row: row,
            };
            return [fromSome(row, Machine), rN];
          };
        };
        const turnCrank = (usr, rNum) => {
          const rN = getRNum(rNum);
          const u = Users[usr];
          const user = fromSome(u, defUser);
          check(user.lastCompletedStep == 1, 'user is on right step');
          chkRows();
          check(isSome(user.rowIndex), 'user was assigned a row index');
          const rowIndex = fromSome(user.rowIndex, 0);
          const nonTakenLngth = loadedRows - emptyRows;
          const maxRindex = nonTakenLngth;
          check(rowIndex <= maxRindex, 'row array bounds check');
          const [_, nArr] = getIfrmArr(rowArr, rowIndex, maxRindex, Address);
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
          const newToksTaken = rowToksTkn + 1;
          const [slot, nSlots] = getIfrmArr(
            slots,
            slotIndex,
            maxIndex,
            Contract
          );
          return () => {
            Users[usr] = {
              ...user,
              lastCompletedStep: 2,
              nftContract: slot,
            };
            Rows[rowKey] = {
              ...rowData,
              slots: nSlots,
              rowToksTkn: newToksTaken,
            };
            return [
              fromSome(slot, thisContract),
              newToksTaken == slots.length ? nArr : rowArr,
              newToksTaken == slots.length ? emptyRows + 1 : emptyRows,
              rN,
            ];
          };
        };
        const finishTurnCrank = (u, rNum) => {
          const rN = getRNum(rNum);
          const user = Users[u];
          const sUser = fromSome(user, defUser);
          check(sUser.lastCompletedStep == 2, 'user is on right step');
          const ctc = fromSome(sUser.nftContract, thisContract);
          return () => {
            const dispenserCtc = remote(ctc, dispenserI);
            const nft = dispenserCtc.setOwner(u);
            check(typeOf(nft) !== null);
            delete Users[u];
            UsersCtcs[u] = ctc;
            return [ctc, rN];
          };
        };
        const reset = (rNum, u) => {
          const rN = getRNum(rNum);
          const user = Users[u];
          const sUser = fromSome(user, defUser);
          check(sUser.lastCompletedStep == 1, 'user has inserted token');
          check(isSome(sUser.row), 'user has row');
          check(isNone(sUser.nftContract), 'user not assigned contract');
          check(totToksTkn > 0, 'there are no tokens taken');
          const sUsrRow = fromSome(sUser.row, Machine);
          const rowData = fromSome(Rows[sUsrRow], defRow);
          const { rowToksTkn, loadedCtcs } = rowData;
          const isRowEmpty = rowToksTkn == loadedCtcs;
          check(isRowEmpty, 'row is not empty');
          return () => {
            transfer([0, [NFT_COST, payToken]]).to(u);
            delete Users[u];
            return rN;
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
          const _ = createRow(this);
        },
        () => handlePmt(0),
        notify => {
          const nRows = createRow(this)();
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
          const _ = loadRow(this, contract);
        },
        (_, _) => handlePmt(0),
        (contract, rNum, notify) => {
          const rN = getRNum(rNum);
          const newRowLoadCount = loadRow(this, contract)();
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
          const _ = insertToken(this, rNum);
        },
        _ => handlePmt(NFT_COST),
        (rNum, notify) => {
          try {
            const [assignedRow, rN] = insertToken(this, rNum)();
            if (assignedRow === Machine) throw 1;
            notify(assignedRow);
            return [
              rN,
              totToksTkn + 1,
              rowArr,
              loadedRows,
              emptyRows,
              createdRows,
              true,
            ];
          } catch (_) {
            transfer([0, [NFT_COST, payToken]]).to(this);
            return defState();
          }
        }
      )
      .api(
        api.turnCrank,
        rNum => {
          const _ = turnCrank(this, rNum);
        },
        _ => handlePmt(0),
        (rNum, notify) => {
          try {
            const [rowForUsr, nArr, eRows, rN] = turnCrank(this, rNum)();
            if (rowForUsr === thisContract) throw 1;
            notify(rowForUsr);
            return [rN, totToksTkn, nArr, loadedRows, eRows, createdRows, true];
          } catch (_) {
            return defState();
          }
        }
      )
      .api(
        api.finishTurnCrank,
        rNum => {
          const _ = finishTurnCrank(this, rNum);
        },
        _ => handlePmt(0),
        (rNum, notify) => {
          const [ctc, rN] = finishTurnCrank(this, rNum)();
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
      )
      .api(
        api.reset,
        rNum => {
          const _ = reset(rNum, this);
        },
        _ => handlePmt(0),
        (rNum, notify) => {
          const rN = reset(rNum, this)();
          notify(null);
          return [
            rN,
            totToksTkn - 1,
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
