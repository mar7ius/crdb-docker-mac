# Used this if method to pass arguments to up: target
# https://stackoverflow.com/a/14061796

ifeq (up,$(firstword $(MAKECMDGOALS)))
  # MAKECMDGOALS is a space-separated list of goals passed to make cmd ( ex: target args1 args2 ... )
  # use the rest as arguments for "up" with wordlist --> $(wordlist s, e, text)
  UP_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
endif

.PHONY: up down

up:
	crdb-cluster/scripts/up.sh $(UP_ARGS)

down:
	crdb-cluster/scripts/down.sh

# Guard clause to turn UP_ARGS into do-nothing targets:
%:
	@:
