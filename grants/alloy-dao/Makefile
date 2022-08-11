.PHONY: default
default:
	echo probably use '`make run`'.
build/index.main.mjs: index.rsh
	reach compile index.rsh
build/test-proposal-contract.main.mjs: test-proposal-contract.rsh
	reach compile test-proposal-contract.rsh
.PHONY: run
run: build/index.main.mjs build/test-proposal-contract.main.mjs
	REACH_CONNECTOR_MODE=ALGO reach run
