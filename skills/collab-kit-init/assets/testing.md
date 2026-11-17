# Test Policy

## Test commands

Use the project commands in `docs/project-rules.md`. Record the exact command and its output. Put measured test counts in the commit message.

## Test layers

- Use fast tests for public contracts and failures that changes in shared code can cause.
- Use user-level tests to check affected behavior through the actual entry point. Record which dependencies are real and which are substitutes.
- Use focused acceptance checks for behavior, visuals, or performance that the fast tests cannot prove. Run an affected slow check before acceptance. Add a permanent test when it protects a contract or prevents a regression.

Record each layer's official command, scope, run trigger, and time limit in the project test policy when these values are known. Follow the general verification rule for scope that a project policy does not cover.

## Before push

Run the tests affected by the change. For shared core code, run the complete set for the affected scope. Give the reason when the change requires the entire project suite. The evidence must cover the final source state. Resolve required failures before push. Record the command, result, elapsed time, and any required check that did not run.
