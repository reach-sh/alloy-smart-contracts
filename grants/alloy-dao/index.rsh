'reach 0.1';
'use strict';

const contractArgSize = 256;

const Action = Data({
  ChangeParams:
  // quorumSize, deadline
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

export const main = Reach.App(() => {
  setOptions({verifyArithmetic: true,});
  const Admin = Participant("Admin", {
    getInit: Fun([], Tuple(Token, UInt, UInt, UInt, UInt)),
    ready: Fun([], Null),
  });
  const User = API({
    propose: Fun([Action], Null),
    unpropose: Fun([UInt], Null),
    support: Fun([ProposalId, UInt], Null),
    unsupport: Fun([ProposalId], Null),
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
  });
  Admin.publish(govToken, govTokenTotal, initPoolSize, quorumSizeInit, deadlineInit);
  commit();
  Admin.pay([0, [initPoolSize, govToken]]);
  const proposalMap = new Map(Address, Proposal);
  const voterMap = new Map(Address, Tuple(ProposalId, UInt));

  Admin.interact.ready();

  const initConfig = {
    quorumSize: quorumSizeInit,
    deadline: deadlineInit,
  };
  const {done, config, govTokensInVotes} =
        parallelReduce({
          done: false,
          config: initConfig,
          govTokensInVotes: 0,
        })
        .invariant(balance(govToken) >= govTokensInVotes)
        .invariant(balance() >= 0)
        .while( ! done )
        .paySpec([govToken])
        .api_(User.propose, (action) => {
          const mCurProp = proposalMap[this];
          check(isNone(mCurProp));
          return [ [0, [0, govToken]], (k) => {
            proposalMap[this] = [thisConsensusTime(), 0, action, false];
            Log.propose([this, thisConsensusTime()], action);
            k(null);
            return {done, config, govTokensInVotes};
          }]
        })
        .api_(User.unpropose, (timestamp) => {
          const mCurProp = proposalMap[this];
          check(isSome(mCurProp));
          const curProp = fromSome(mCurProp, [0, 0, Action.Noop(), false]);
          const [time, _, _, _] = curProp;
          check(timestamp == time);
          return [ [0, [0, govToken]], (k) => {
            delete proposalMap[this];
            Log.unpropose([this, timestamp]);
            k(null);
            return {done, config, govTokensInVotes};
          }];
        })
        .api_(User.getUntrackedFunds, () => {
          return [ [0, [0, govToken]], (k) => {
            k(null);
            const _ = getUntrackedFunds();
            const _ = getUntrackedFunds(govToken);
            return {done, config, govTokensInVotes};
          }];
        })
        .api_(User.support, ([proposer, proposalTime], voteAmount) => {
          // Check that the proposal exists and that the voter doesn't currently support anything.
          const voter = this;
          const mProp = proposalMap[proposer];
          const [curPropTime, curPropVotes, action, alreadyCompleted] =
                fromSome(mProp, [0, 0, Action.Noop(), false]);
          check(curPropTime != 0);
          check(curPropTime == proposalTime);
          check(!alreadyCompleted);
          canAdd(proposalTime, config.deadline);
          check(proposalTime + config.deadline <= thisConsensusTime());
          canAdd(govTokensInVotes, voteAmount);
          canAdd(voteAmount, curPropVotes);
          const mVoterCurrentSupport = voterMap[voter];
          check(mVoterCurrentSupport == Maybe(Tuple(ProposalId, UInt)).None());
          const newGovTokensInVotes = govTokensInVotes + voteAmount;

          action.match({
            Payment: (([_, networkAmt, govAmt]) => {
              canAdd(newGovTokensInVotes, govAmt);
              // TODO - I feel like these should be require specifically, not check, but that would require the other API form.
              check(balance() >= networkAmt);
              check(balance(govToken) >= newGovTokensInVotes + govAmt);
            }),
            CallContract: (([_, networkAmt, govAmt, _]) => {
              canAdd(newGovTokensInVotes, govAmt);
              // TODO - I feel like these should be require specifically, not check, but that would require the other API form.
              check(balance() >= networkAmt);
              check(balance(govToken) >= govAmt + newGovTokensInVotes);
            }),
            default: (_) => {return;},
          });

          return [ [0, [voteAmount, govToken]], (k) => {
            const newPropVotes = curPropVotes + voteAmount;
            // TODO - I'm not really sure if the quorum is supposed to be just an integer or if it's supposed to represent a fraction of the tokens not held by the dao or what.  For now it's just the number of tokens needed.
            // TODO - Jay's notes say something about 5 decimals of accuracy for this.  I'm not sure what that means, because tokens are atomic units, so we know exactly whether the quorum size is met or not.  Maybe this indicates that the quorum should be a fraction.
            const enoughVotes = newPropVotes > config.quorumSize;
            const newProp = [proposalTime, newPropVotes, action, enoughVotes];
            proposalMap[proposer] = newProp;
            voterMap[voter] = [[proposer, proposalTime], voteAmount];
            Log.support(voter, voteAmount, [proposer, proposalTime])

            if (enoughVotes) {
              action.match({
                Payment: (([toAddr, networkAmt, govAmt]) => {
                  transfer([networkAmt, [govAmt, govToken]]).to(toAddr);
                }),
                CallContract: (([contract, networkAmt, govAmt, callData]) => {
                  const rc = remote(contract, {
                    go: Fun([Bytes(contractArgSize)], Null),
                  });
                  rc.go.pay([networkAmt, [govAmt, govToken]])(callData);
                }),
                default: (_) => {return;},
              });

              Log.executed([proposer, proposalTime]);
            }

            k(null);
            const newConfig = enoughVotes
                  ? action.match({
                    ChangeParams: (([quorumSize, deadline]) => ({quorumSize, deadline})),
                    default: (_) => config,
                  })
                  : config
            return {
              done,
              config: newConfig,
              govTokensInVotes: newGovTokensInVotes,
            };
          }];
        })
        .api_(User.unsupport, ([proposer, proposalTime]) => {
          const voter = this;
          const mVote = voterMap[voter];
          check(isSome(mVote));
          const [_, amount] = fromSome(mVote, [[voter, 0], 0]);
          // TODO - I feel like this should be require specifically, not check, but then I need to switch to the other API form.
          check(amount < govTokensInVotes);
          const mProp = proposalMap[proposer];
          const newProp = mProp.match({
            None: () => {return [0, 0, Action.Noop(), false];},
            Some: ([time, votes, act, executed]) => {
              check(votes > amount);
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
              govTokensInVotes: govTokensInVotes - amount,
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
