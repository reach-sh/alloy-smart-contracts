import { loadStdlib } from '@reach-sh/stdlib'
import * as authorityBackend from './build/authority.main.mjs'
import * as dispenserBackend from './build/dispenser.main.mjs'

const stdlib = loadStdlib()
const { launchToken } = stdlib

const createNFts = (acc, amt) =>
  new Promise(async resolve => {
    const pms = []
    for (let i = 0; i < amt; i++) {
      pms.push(launchToken(acc, `Cool NFT | edition ${i}`, `NFT${i}`))
    }
    const nfts = await Promise.all(pms)
    resolve(nfts)
  })

const createNftCtcs = (acc, nfts) =>
  nfts.map(nft => acc.contract(dispenserBackend))

const deployNftCtcs = nftCtcs =>
  new Promise((resolve, reject) => {
    let ctcAddress = []
    let i = 0
    const deployCtc = () => {
      if (i === nftCtcs.length) {
        resolve(ctcAddress)
        return
      }
      nftCtcs[i].p.Machine({
        ready: ctc => {
          ctcAddress.push(ctc)
          deployCtc(i++)
        },
      })
    }
    deployCtc()
  })

const loadNfts = (nftCtcAdds, ctc) =>
  new Promise(async (resolve, reject) => {
    const pms = nftCtcAdds.map(ctcAdd => ctc.a.load(ctcAdd))
    const resolved = await Promise.all(pms)
    const fmt = resolved.map(res => stdlib.bigNumberToNumber(res))
    console.log('loaded these contracts:', fmt)
    resolve(resolved)
  })

// starting balance
const bal = stdlib.parseCurrency(10000)

try {
  const gasLimit = 5000000
  // create users
  const accOwner = await stdlib.newTestAccount(bal)
  const accUser = await stdlib.newTestAccount(bal)

  // create pay token
  const { id: payTokenId } = await launchToken(
    accOwner,
    'Reach Thank You',
    'RTYT'
  )
  await accUser.tokenAccept(payTokenId)
  await stdlib.transfer(accOwner, accUser, 100, payTokenId)

  // create, deploy and load NFT's
  const nfts = await createNFts(accOwner, 9)
  const nftCtcs = createNftCtcs(accOwner, nfts)
  const nftCtcAdds = await deployNftCtcs(nftCtcs)

  // create machine contract
  const ctcOwner = accOwner.contract(authorityBackend)

  // on machine contract deploy callback
  const onAppDeploy = async () => {
    console.log('App deployed!')
    try {
      const info = await ctcOwner.getInfo()
      await loadNfts(nftCtcAdds, ctcOwner)
      console.log(`Successfully loaded ${nftCtcAdds.length} contracts!`)
      await new Promise(r => setTimeout(r, 3000))
      const ctcUser = accUser.contract(authorityBackend, info)
      await new Promise(r => setTimeout(r, 3000))
      const { insertToken } = ctcUser.a
      const y = await insertToken(stdlib.bigNumberify(2))
      console.log('yay!')
    } catch (err) {
      console.log('Oops', err)
    }
  }

  await ctcOwner.p.Machine({
    payToken: payTokenId,
    ready: onAppDeploy,
  })
} catch (err) {
  console.log('Error:', err)
}
