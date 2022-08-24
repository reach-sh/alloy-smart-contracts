.PHONY: default
default:
	echo probably use '`make run`'.
build/dao.main.mjs: dao.rsh
	REACH_DEBUG=1 reach compile dao.rsh
build/test-proposal-contract.main.mjs: test-proposal-contract.rsh
	REACH_DEBUG=1 reach compile test-proposal-contract.rsh
.PHONY: run
run: build/dao.main.mjs build/test-proposal-contract.main.mjs
	REACH_NO_WARN=1 REACH_DEBUG=0 REACH_CONNECTOR_MODE=ALGO reach run dao
.PHONY: run-test-test
run-test-test: build/test-proposal-contract.main.mjs
	REACH_NO_WARN=1 REACH_DEBUG=0 REACH_CONNECTOR_MODE=ALGO reach run test-proposal-contract
