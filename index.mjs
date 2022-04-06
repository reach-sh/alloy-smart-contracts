import { loadStdlib } from '@reach-sh/stdlib'
import * as backend from './build/index.main.mjs'

const program = async () => {
  const stdlib = loadStdlib()
  const { launchToken } = stdlib

  const bal = stdlib.parseCurrency(100)

  const accOwner = await stdlib.newTestAccount(bal)
  const accUser = await stdlib.newTestAccount(bal)

  const payToken = await launchToken(accOwner, 'Reach Thank You', 'RTYT')
  console.log('payToken', payToken)

  const ctcOwner = accOwner.contract(backend)

  const info = ctcOwner.getInfo()

  const onAppDeploy = async () => {
    console.log('App deployed!')
    try {
      const ctcUser = accUser.contract(backend, info)
    } catch (err) {}
  }

  await backend.Owner(ctcOwner, {
    getRNum: () => Math.floor(Math.random() * 10000000),
    ready: onAppDeploy,
  })
}

program()
