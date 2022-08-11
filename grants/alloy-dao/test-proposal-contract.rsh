'reach 0.1';
'use strict';

const contractArgSize = 256;

export const main = Reach.App(() => {
  const Admin = Participant("Admin", {
    getInit: Fun([], Tuple(Address, Address, UInt, Token)),
    ready: Fun([], Null),
  });
  const GO = API({
    go: Fun([Bytes(contractArgSize)], Null),
  });

  init();

  Admin.only(() => {
    const [payer, payee, paymentAmt, govToken] = declassify(interact.getInit());
    check(paymentAmt < UInt.max / 2);
  });
  Admin.publish(payer, payee, paymentAmt, govToken);
  commit();
  Admin.interact.ready();

  //const [[_], k1] = call(GO.go).pay((_) => {return [paymentAmt, [0, govToken]]});
  const [[_], k1] = call(GO.go).pay((_) => {return [0, [0, govToken]]});
  //const [[_], k1] = call(GO.go);
  // Require a specific payer so the DAO can't be attacked by someone else doing it during voting.
  //enforce(this == payer);
  //transfer(paymentAmt / 2).to(payee);
  k1(null);
  commit();

  const [[bs], k2] = call(GO.go).pay((_) => {return [0, [0, govToken]]});
  enforce(this == payer);
  void getUntrackedFunds();
  void bs
  //if (bs == Bytes(contractArgSize).pad("pay")) {
  //  transfer(balance()).to(payee);
  //} else {
  //  // Else we return the payment
  //  transfer(balance()).to(payer);
  //}
  k2(null);
  commit();

  // TODO - remove this...
  Admin.publish();
  transfer(balance()).to(Admin);
  transfer(balance(govToken)).to(Admin);
  commit();


});
