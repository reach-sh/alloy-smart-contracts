'reach 0.1';
'use strict';

const contractArgSize = 256;
const quorumMax = 100_000;

const Action = Data({
  ChangeParams:
  // quorumSize (in millipercent, or per-hundred-thousand), deadline
  Tuple(UInt, UInt),
  Payment:
  // to, network, govToken
  Tuple(Address, UInt, UInt),
  CallContract:
  // ctc, network, govToken, call argument
  Tuple(Contract, UInt, UInt, Bytes(contractArgSize)),
  Noop: Null,
});

const Proposal = Tuple(
  // TODO - real proposals should probably have a text field that can contain eg. an IPFS link to a high-level explanation, argument, etc.
  UInt, // proposedTime
  UInt, // totalVotes
  Action,
  Bool // completed
);

const ProposalId = Tuple(
  Address, // proposer's address
  UInt // time of proposal creation
);

const canAdd = (a,b) => {
  check(a < UInt.max - b);
};
const canSub = (a,b) => {
  check(a > b);
};
const canMul = (a,b) => {
  check(UInt.max / a >= b);
};
const canMul256 = (a,b) => {
  check(UInt256.max / a >= b);
};

export const main = Reach.App(() => {
  setOptions({verifyArithmetic: true,});
  const Admin = Participant("Admin", {
    getInit: Fun([], Tuple(Token, UInt, UInt, UInt, UInt)),
    ready: Fun([], Null),
  });
  const User = API({
    propose: Fun([Action], Null),
    unpropose: Fun([ProposalId], Null),
    support: Fun([ProposalId, UInt], Null),
    unsupport: Fun([ProposalId], Null),
    fund: Fun([UInt, UInt], Null),
    getUntrackedFunds: Fun([], Null),
  });
  const Log = Events("Log", {
    propose: [ProposalId, Action],
    unpropose: [ProposalId],
    support: [Address, UInt, ProposalId],
    unsupport: [Address, UInt, ProposalId],
    executed: [ProposalId],
  });
  init();


  Admin.only(() => {
    const [govToken, govTokenTotal, initPoolSize, quorumSizeInit, deadlineInit] =
          declassify(interact.getInit());
    check(govTokenTotal > initPoolSize);
    canMul256(UInt256(quorumMax), UInt256(govTokenTotal));
    check(UInt.max / quorumMax >= govTokenTotal);
    check(quorumSizeInit <= quorumMax);
  });
  Admin.publish(govToken, govTokenTotal, initPoolSize, quorumSizeInit, deadlineInit);
  check(govTokenTotal > initPoolSize);
  canMul256(UInt256(quorumMax), UInt256(govTokenTotal));
  check(quorumSizeInit <= quorumMax);
  commit();

  Admin.pay([0, [initPoolSize, govToken]]);
  const proposalMap = new Map(Address, Proposal);
  const voterMap = new Map(Address, Tuple(ProposalId, UInt));

  Admin.interact.ready();

  const initConfig = {
    quorumSize: quorumSizeInit,
    deadline: deadlineInit,
  };
  const initTreasury = {
    net: balance(),
    gov: balance(govToken),
  };
  const {done, config, treasury, govTokensInVotes} =
        parallelReduce({
          done: false,
          config: initConfig,
          treasury: initTreasury,
          govTokensInVotes: 0,
        })
        .invariant(govTokenTotal >= treasury.gov)
        .invariant(govTokenTotal >= govTokensInVotes)
        .invariant(UInt.max - treasury.gov >= govTokensInVotes)
        .invariant(govTokenTotal >= treasury.gov + govTokensInVotes)
        .invariant(balance(govToken) == treasury.gov + govTokensInVotes)
        .invariant(balance() == treasury.net)
        .invariant(balance() >= 0)
        .invariant(config.quorumSize <= quorumMax)
        .while( ! done )
        .paySpec([govToken])
        .api_(User.propose, (action) => {
          const mCurProp = proposalMap[this];
          check(isNone(mCurProp));
          return [ [0, [0, govToken]], (k) => {
            const now = thisConsensusTime();
            proposalMap[this] = [now, 0, action, false];
            Log.propose([this, now], action);
            k(null);
            return {done, config, treasury, govTokensInVotes};
          }]
        })
        .api_(User.unpropose, ([addr, timestamp]) => {
          check(addr == this);
          const mCurProp = proposalMap[this];
          check(isSome(mCurProp));
          const curProp = fromSome(mCurProp, [0, 0, Action.Noop(), false]);
          const [time, _, _, _] = curProp;
          check(timestamp == time);
          return [ [0, [0, govToken]], (k) => {
            delete proposalMap[this];
            Log.unpropose([this, timestamp]);
            k(null);
            return {done, config, treasury, govTokensInVotes};
          }];
        })
        .api_(User.getUntrackedFunds, () => {
          return [ [0, [0, govToken]], (k) => {
            k(null);
            const utNet = getUntrackedFunds();
            const utGov = getUntrackedFunds(govToken);
            enforce(govTokenTotal >= utGov);
            enforce(govTokenTotal - utGov >= treasury.gov + govTokensInVotes);
            return {
              done, config, govTokensInVotes,
              treasury: {net: treasury.net + utNet, gov: treasury.gov + utGov},
            };
          }];
        })
        .api_(User.support, ([proposer, proposalTime], voteAmount) => {
          // Check that the proposal exists and that the voter doesn't currently support anything.
          const voter = this;
          const mProp = proposalMap[proposer];
          const [curPropTime, curPropVotes, action, alreadyCompleted] =
                fromSome(mProp, [0, 0, Action.Noop(), false]);
          check(govTokenTotal >= voteAmount);
          check(govTokenTotal - voteAmount >= treasury.gov + govTokensInVotes);
          check(curPropTime != 0, "time not zero");
          check(curPropTime == proposalTime, "timestamp matches current proposal for address");
          check(!alreadyCompleted, "proposal not already done");
          canAdd(proposalTime, config.deadline);
          enforce(thisConsensusTime() <= proposalTime + config.deadline, "proposal not past deadline");
          canAdd(govTokensInVotes, voteAmount);
          canAdd(voteAmount, curPropVotes);
          const mVoterCurrentSupport = voterMap[voter];
          check(mVoterCurrentSupport == Maybe(Tuple(ProposalId, UInt)).None(), "voter not supporting other already");
          const newGovTokensInVotes = govTokensInVotes + voteAmount;
          const newPropVotes = curPropVotes + voteAmount;
          const totalVotes = govTokenTotal - treasury.gov;
          check(newPropVotes <= totalVotes);
          // Here we allow support to pass with 0 votes if the DAO somehow holds all the tokens.  But really this is mostly there because if I don't rule out the case where totalVotes is zero, the SMT solver can't verify that this multiplication won't overflow because SMT proves that by using division, and SMT defines division by zero as zero.  So without this special case I get verification failure witnesses that include division by zero.
          const pass = totalVotes == 0 || UInt256(newPropVotes) * UInt256(quorumMax) > UInt256(config.quorumSize) * UInt256(totalVotes);

          action.match({
            ChangeParams: ([quorumSize, _]) => {
              check(quorumSize <= quorumMax);
            },
            Payment: (([_, networkAmt, govAmt]) => {
              canAdd(newGovTokensInVotes, govAmt);
              if (pass) {
                check(treasury.net >= networkAmt, "NT balance greater than pay amount");
                check(treasury.gov >= govAmt, "GT balance greater than pay amount");
              }
            }),
            CallContract: (([_, networkAmt, govAmt, _]) => {
              canAdd(newGovTokensInVotes, govAmt);
              if (pass) {
                check(treasury.net >= networkAmt, "NT balance greater than pay amount");
                check(treasury.gov >= govAmt, "GT balance greater than pay amount");
              }
            }),
            default: (_) => {return;},
          });

          return [ [0, [voteAmount, govToken]], (k) => {
            const newProp = [proposalTime, newPropVotes, action, pass];
            proposalMap[proposer] = newProp;
            voterMap[voter] = [[proposer, proposalTime], voteAmount];
            Log.support(voter, voteAmount, [proposer, proposalTime])

            const exec = () => {
              if (pass) {
                const retval = action.match({
                  Payment: (([toAddr, networkAmt, govAmt]) => {
                    transfer([networkAmt, [govAmt, govToken]]).to(toAddr);
                    return [networkAmt, govAmt];
                  }),
                  CallContract: (([contract, networkAmt, govAmt, callData]) => {
                    const rc = remote(contract, {
                      go: Fun([Bytes(contractArgSize)], Null),
                    });
                    void rc.go.pay([networkAmt, [govAmt, govToken]])(callData);
                    return [networkAmt, govAmt];
                  }),
                  default: (_) => {return [0,0];},
                });

                Log.executed([proposer, proposalTime]);
                return retval;
              } else {
                return [0,0];
              }
            }
            const [netSpend, govSpend] = exec();

            k(null);
            const newConfig = pass
                  ? action.match({
                    ChangeParams: (([quorumSize, deadline]) => ({quorumSize, deadline})),
                    default: (_) => config,
                  })
                  : config;
            const newTreasury = pass ?
                  {
                    net: treasury.net - netSpend,
                    gov: treasury.gov - govSpend,
                  }
                  : treasury;
            return {
              done,
              config: newConfig,
              treasury: newTreasury,
              govTokensInVotes: newGovTokensInVotes,
            };
          }];
        })
        .api_(User.unsupport, ([proposer, proposalTime]) => {
          const voter = this;
          const mVote = voterMap[voter];
          check(isSome(mVote), "voter is supporting a proposal");
          const [_, amount] = fromSome(mVote, [[voter, 0], 0]);
          check(amount <= govTokensInVotes, "the contract has the voter's tokens");
          const mProp = proposalMap[proposer];
          const newProp = mProp.match({
            None: () => {return [0, 0, Action.Noop(), false];},
            Some: ([time, votes, act, executed]) => {
              check(votes >= amount, "the proposal has the voter's tokens");
              return [time, votes - amount, act, executed];
            },
          });
          return [ [0, [0, govToken]], (k) => {
            delete voterMap[voter];
            if (isSome(mProp)){
              proposalMap[proposer] = newProp;
            }
            transfer([0, [amount, govToken]]).to(voter);
            Log.unsupport(voter, amount, [proposer, proposalTime]);
            k(null);
            return {
              done,
              config,
              treasury,
              govTokensInVotes: govTokensInVotes - amount,
            };
          }];
        })
        .api_(User.fund, (netAmt, govAmt) => {
          check(govTokenTotal >= govAmt);
          check(govTokenTotal - govAmt >= treasury.gov + govTokensInVotes);
          return [ [netAmt, [govAmt, govToken]], (k) => {
            k(null);
            const nt = {
              net: treasury.net + netAmt,
              gov: treasury.gov + govAmt,
            }
            return {done, config, treasury: nt, govTokensInVotes,};
          }];
        })
        .timeout(false);
  commit();

  Admin.publish();
  const _ = getUntrackedFunds();
  const _ = getUntrackedFunds(govToken);
  transfer([balance(), [balance(govToken), govToken]]).to(Admin);
  commit();

  exit();
});
