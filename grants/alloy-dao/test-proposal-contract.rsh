'reach 0.1';
'use strict';

const contractArgSize = 256;

export const main = Reach.App(() => {
  const Admin = Participant("Admin", {
    getInit: Fun([], Tuple(Address, Address, UInt, UInt, Token, UInt, UInt)),
    ready: Fun([], Null),
  });
  const GO = API({
    go: Fun([Bytes(contractArgSize)], Null),
  });

  init();

  Admin.only(() => {
    const [payer, payee, paymentAmt, govAmt, govToken, payAmtZero, govAmtZero] = declassify(interact.getInit());
    check(paymentAmt < UInt.max / 2);
  });
  Admin.publish(payer, payee, paymentAmt, govAmt, govToken, payAmtZero, govAmtZero);
  commit();
  Admin.interact.ready();

  const [[_], k1] = call(GO.go).pay((_) => {return [paymentAmt, [govAmt, govToken]]});
  // Require a specific payer so the DAO can't be attacked by someone else doing it during voting.
  enforce(this == payer);
  // TODO - I can't seem to get this transfer to work when called by a contract...
  transfer([paymentAmt / 2, [govAmt / 2, govToken]]).to(payee);
  k1(null);
  commit();

  // There payAmtZero/govAmtZero should just be literal zeroes... except that those pay amounts are then optimized away, changing the expected transaction group size on Algorand.
  const [[bs], k2] = call(GO.go).pay((_) => {return [payAmtZero, [govAmtZero, govToken]]});
  enforce(this == payer);
  void getUntrackedFunds();
  void bs
  if (bs == Bytes(contractArgSize).pad("pay")) {
    transfer([balance(), [balance(govToken), govToken]]).to(payee);
  } else {
    // Else we return the payment
    transfer([balance(), [balance(govToken), govToken]]).to(payer);
  }
  k2(null);
  commit();

  // TODO - remove this...
  Admin.publish();
  transfer([balance(), [balance(govToken), govToken]]).to(Admin);
  commit();


});
