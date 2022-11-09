import {loadStdlib} from '@reach-sh/stdlib';
import * as daoContract from './build/dao.main.mjs';
import * as testProposalContract from './build/test-proposal-contract.main.mjs';

import {runCoreTests} from './dao-core-tests.mjs';

await runCoreTests();
