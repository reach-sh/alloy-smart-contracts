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
  nfts.map(nft => ({
    nft,
    ctc: acc.contract(dispenserBackend),
  }))

const deployNftCtcs = nftCtcs =>
  new Promise((resolve, reject) => {
    let ctcAddress = []
    let i = 0
    const deployCtc = () => {
      if (i === nftCtcs.length) {
        resolve(ctcAddress)
        return
      }
      nftCtcs[i].ctc.p.Machine({
        ready: ctc => {
          ctcAddress.push(ctc)
          deployCtc(i++)
        },
        nft: nftCtcs[i].nft.id,
      })
    }
    deployCtc()
  })

const loadNfts = (nftCtcAdds, ctc) =>
  new Promise(async (resolve, reject) => {
    const pms = nftCtcAdds.map(ctcAdd => ctc.a.load(ctcAdd))
    const resolved = await Promise.all(pms)
    const fmt = resolved.map(res => stdlib.bigNumberToNumber(res))
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
      const balTYTBefore = await stdlib.balanceOf(accUser, payTokenId)
      const fmtBalTYTBEfore = stdlib.bigNumberToNumber(balTYTBefore)
      console.log('balance of TYT Token before', fmtBalTYTBEfore)

      const info = await ctcOwner.getInfo()
      await loadNfts(nftCtcAdds, ctcOwner)
      console.log(`Successfully loaded ${nftCtcAdds.length} contracts!`)

      const ctcUser = accUser.contract(authorityBackend, info)
      const { insertToken, turnCrank } = ctcUser.a
      const usrCtc = await insertToken(stdlib.bigNumberify(2))
      const fmtCtc = stdlib.bigNumberToNumber(usrCtc)
      console.log('Your NFT ctc is:', fmtCtc)
      
      const [nft, ctcWithNft] = await turnCrank()
      const fmtNft = stdlib.bigNumberToNumber(nft)

      const balUserBefore = await stdlib.balanceOf(accUser, fmtNft)
      const fmtBalUserBefore = stdlib.bigNumberToNumber(balUserBefore)
      console.log('balance of NFT before', fmtBalUserBefore)

      await accUser.tokenAccept(fmtNft)
      const fmtCtcWnft = stdlib.bigNumberToNumber(ctcWithNft)
      console.log('This contract is ready for you to get your NFT:', fmtCtcWnft)
      const nftCtcUser = accUser.contract(dispenserBackend, ctcWithNft)
      const { getNft } = nftCtcUser.a
      const t = await getNft()

      const balTYTAfter = await stdlib.balanceOf(accUser, payTokenId)
      const fmtBalTYTAfter = stdlib.bigNumberToNumber(balTYTAfter)
      console.log('balance of TYT Token after', fmtBalTYTAfter)

      const balUserAfter = await stdlib.balanceOf(accUser, fmtNft)
      const fmtBalUserAfter = stdlib.bigNumberToNumber(balUserAfter)
      console.log('balance of NFT after', fmtBalUserAfter)

      process.exit(0)

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
