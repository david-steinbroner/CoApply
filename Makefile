# CoApply — developer/user convenience targets.
# `make hub` starts the local hub with NO Claude Code and NO tokens (see scripts/hub.sh).

.PHONY: hub help

hub:  ## Start the CoApply hub locally (no Claude, no tokens) → http://127.0.0.1:7878/
	@bash scripts/hub.sh

help:  ## List available make targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | sed -E 's/:.*## /\t/' | sort | column -t -s "$$(printf '\t')"
