'reach 0.1';
'use strict';

export const contractArgSize = 128;
const proposalTextSize = 128;
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
  UInt, // proposedTime
  UInt, // totalVotes
  Action,
  Bytes(proposalTextSize), // text field primarily for links
  Bool // completed
);

// A fake proposal object for when I need to get data out of a maybe but its use is guarded by isSome.
const dummyProposal = [0, 0, Action.Noop(), Bytes(proposalTextSize).pad(""), false];
const someProp = (mprop) => {
  check(isSome(mprop));
  return fromSome(mprop, dummyProposal);
}

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
  check(a == 0 || UInt.max / a >= b);
};
const canMul256 = (a,b) => {
  check(a == UInt256(0) || UInt256.max / a >= b);
};

export const main = Reach.App(() => {
  setOptions({verifyArithmetic: true,});
  const Admin = Participant("Admin", {
    getInit: Fun([], Tuple(Token, UInt, UInt, UInt, UInt)),
    ready: Fun([], Null),
  });
  const User = API({
    propose: Fun([Action, Bytes(proposalTextSize)], Null),
    unpropose: Fun([ProposalId], Null),
    support: Fun([ProposalId, UInt], Null),
    unsupport: Fun([ProposalId], Null),
    execute: Fun([ProposalId], Null),
    fund: Fun([UInt, UInt], Null),
    getUntrackedFunds: Fun([], Null),
  });
  const Log = Events("Log", {
    propose: [ProposalId, Action, Bytes(proposalTextSize)],
    unpropose: [ProposalId],
    support: [Address, UInt, ProposalId],
    unsupport: [Address, UInt, ProposalId],
    executed: [ProposalId],
  });
  init();


  Admin.only(() => {
    // Note that it is critical that the admin be honest about the govTokenTotal -- the total number of government tokens that exist.  If the admin gives a number lower that the true number, this contract can be bricked.  With any incorrect number it defeats the logic of checking whether a proposal passes.  This contract also assumes no clawback or freezing of the government token.
    const [govToken, govTokenTotal, initPoolSize, quorumSizeInit, deadlineInit] =
          declassify(interact.getInit());
  });
  Admin.publish(govToken, govTokenTotal, initPoolSize, quorumSizeInit, deadlineInit)
    .check(() => {
      check(govTokenTotal > initPoolSize);
      canMul256(UInt256(quorumMax), UInt256(govTokenTotal));
      check(UInt.max / quorumMax >= govTokenTotal);
      check(quorumSizeInit <= quorumMax);
  });
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
    net: 0,
    gov: initPoolSize,
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
        .invariant(config.quorumSize <= quorumMax)
        .while( ! done )
        .paySpec([govToken])
        .define(() => {
          const livePropChecks = ([proposer, proposalTime]) => {
            const mProp = proposalMap[proposer];
            const prop = someProp(mProp);
            const [curPropTime, _, _, _, alreadyCompleted] = prop;
            check(curPropTime != 0, "time not zero");
            check(curPropTime == proposalTime, "timestamp matches current proposal for address");
            check(!alreadyCompleted, "proposal not already done");
            canAdd(proposalTime, config.deadline);
            enforce(thisConsensusTime() <= proposalTime + config.deadline, "proposal not past deadline");
            return prop;
          }
        })
        .api_(User.propose, (action, message) => {
          const mCurProp = proposalMap[this];
          check(isNone(mCurProp));
          // Disallow Noop proposals.  They only exist to simplify writing code with Maybe proposals.
          check(action.match({Noop: ((_) => false), default: ((_) => true)}));
          return [ [0, [0, govToken]], (k) => {
            const now = thisConsensusTime();
            proposalMap[this] = [now, 0, action, message, false];
            Log.propose([this, now], action, message);
            k(null);
            return {done, config, treasury, govTokensInVotes};
          }]
        })
        .api_(User.unpropose, ([addr, timestamp]) => {
          check(addr == this);
          const mCurProp = proposalMap[this];
          check(isSome(mCurProp));
          const curProp = someProp(mCurProp);
          const [time, _, _, _, _] = curProp;
          check(timestamp == time);
          return [ [0, [0, govToken]], (k) => {
            delete proposalMap[this];
            Log.unpropose([this, timestamp]);
            k(null);
            return {done, config, treasury, govTokensInVotes};
          }];
        })
        .api_(User.execute, ([proposer, proposalTime]) => {
          // Check that the proposal exists and that the voter doesn't currently support anything.
          const [_, curPropVotes, action, message, _] =
                livePropChecks([proposer, proposalTime]);
          const totalVotes = govTokenTotal - treasury.gov;
          canMul256(UInt256(curPropVotes), UInt256(quorumMax));
          canMul256(UInt256(config.quorumSize), UInt256(totalVotes));
          const pass = UInt256(curPropVotes) * UInt256(quorumMax) > UInt256(config.quorumSize) * UInt256(totalVotes);
          check(pass, "proposal has passed");

          action.match({
            ChangeParams: ([quorumSize, _]) => {
              check(quorumSize <= quorumMax);
            },
            Payment: (([_, networkAmt, govAmt]) => {
              if (pass) {
                check(treasury.net >= networkAmt, "NT balance greater than pay amount");
                check(treasury.gov >= govAmt, "GT balance greater than pay amount");
              }
            }),
            CallContract: (([_, networkAmt, govAmt, _]) => {
              if (pass) {
                check(treasury.net >= networkAmt, "NT balance greater than pay amount");
                check(treasury.gov >= govAmt, "GT balance greater than pay amount");
              }
            }),
            default: (_) => {return;},
          });

          return [ [0, [0, govToken]], (k) => {
            const newProp = [proposalTime, curPropVotes, action, message, pass];
            proposalMap[proposer] = newProp;

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
              govTokensInVotes,
            };
          }];
        })
        .api_(User.support, ([proposer, proposalTime], voteAmount) => {
          // Check that the proposal exists and that the voter doesn't currently support anything.
          const voter = this;
          const [_, curPropVotes, action, message, alreadyCompleted] =
                livePropChecks([proposer, proposalTime]);
          check(govTokenTotal >= voteAmount);
          check(govTokenTotal - voteAmount >= treasury.gov + govTokensInVotes);
          canAdd(govTokensInVotes, voteAmount);
          canAdd(voteAmount, curPropVotes);
          const mVoterCurrentSupport = voterMap[voter];
          check(mVoterCurrentSupport == Maybe(Tuple(ProposalId, UInt)).None(), "voter not supporting other already");
          const newGovTokensInVotes = govTokensInVotes + voteAmount;
          const newPropVotes = curPropVotes + voteAmount;
          const totalVotes = govTokenTotal - treasury.gov;
          check(newPropVotes <= totalVotes);


          return [ [0, [voteAmount, govToken]], (k) => {
            const newProp = [proposalTime, newPropVotes, action, message, alreadyCompleted];
            proposalMap[proposer] = newProp;
            voterMap[voter] = [[proposer, proposalTime], voteAmount];
            Log.support(voter, voteAmount, [proposer, proposalTime])

            k(null);
            return {
              done,
              config,
              treasury,
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
            None: () => {return dummyProposal;},
            Some: ([time, votes, act, message, executed]) => {
              check(votes >= amount, "the proposal has the voter's tokens");
              return [time, votes - amount, act, message, executed];
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
        .timeout(false);
  commit();

  Admin.publish();
  const _ = getUntrackedFunds();
  const _ = getUntrackedFunds(govToken);
  transfer([balance(), [balance(govToken), govToken]]).to(Admin);
  commit();

  exit();
});
