.PHONY: default
default:
	echo probably use '`make run`'.
build/dao.main.mjs: dao.rsh
	REACH_DEBUG=y reach compile dao.rsh
build/test-proposal-contract.main.mjs: test-proposal-contract.rsh
	REACH_DEBUG=y reach compile test-proposal-contract.rsh
.PHONY: run
run: build/dao.main.mjs build/test-proposal-contract.main.mjs
	REACH_DEBUG=y REACH_CONNECTOR_MODE=ALGO reach run dao
.PHONY: run-test-test
run-test-test: build/test-proposal-contract.main.mjs
	REACH_CONNECTOR_MODE=ALGO reach run test-proposal-contract
