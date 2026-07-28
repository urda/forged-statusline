########################################################################################################################
# Configuration & Variables
########################################################################################################################

#-----------------------------------------------------------
# General Configuration
#-----------------------------------------------------------

SHELL := /bin/bash
SHELLCHECK := shellcheck

.DELETE_ON_ERROR:

#-----------------------------------------------------------
# Project-Specific Configuration
#-----------------------------------------------------------

INSTALL_SCRIPT := ./install.sh
INSTALL_TEST_SCRIPT := ./scripts/test-install.sh
STATUSLINE_LOCAL := ./urda-com-forged-statusline.sh
STATUSLINE_TEST_SCRIPT := ./scripts/test-urda-com-forged-statusline.sh

########################################################################################################################
# Commands
########################################################################################################################

# Keep help first so bare `make` displays it.
.PHONY: help
help: # Show this help screen
	@grep -E '^[a-zA-Z_-]+:.*# .*$$' ${MAKEFILE_LIST} |\
	sort -t: -k1,1 |\
	awk 'BEGIN {FS = ":.*?# "}; {printf "\033[1m%-36s\033[0m %s\n", $$1, $$2}'

########################################################################################################################

.PHONY: lint
lint: # Run shellcheck.
	${SHELLCHECK} "${STATUSLINE_LOCAL}" "${STATUSLINE_TEST_SCRIPT}" "${INSTALL_SCRIPT}" "${INSTALL_TEST_SCRIPT}"

.PHONY: test
test: version-check test-statusline test-install # Run every test suite, as CI's test job does. Lint runs separately.

.PHONY: test-install
test-install: # Test installer atomicity.
	${INSTALL_TEST_SCRIPT}

.PHONY: test-statusline
test-statusline: # Test the renderer.
	set -o pipefail; ${STATUSLINE_TEST_SCRIPT} 2>&1 | grep -E '\[(PASS|FAIL)\]|passed'

.PHONY: test-statusline-verbose
test-statusline-verbose: # Test with rendered output.
	${STATUSLINE_TEST_SCRIPT}

.PHONY: version-check
version-check: # Compare VERSION with the renderer.
	@file_ver="$$(cat VERSION)"; \
	script_ver="$$(grep -oE 'VERSION:-[0-9]+\.[0-9]+\.[0-9]+' "${STATUSLINE_LOCAL}" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"; \
	if [ "$$file_ver" = "$$script_ver" ]; then \
		echo "VERSION matches '$$script_ver'"; \
	else \
		echo "VERSION mismatch: VERSION='$$file_ver', script='$$script_ver'"; \
		exit 1; \
	fi
