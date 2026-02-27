# Multi-agent Relay Protocol

Use this protocol to emulate Agent Teams communication with Team Lead as the message bus.

## Envelope

Every cross-agent message must be wrapped as:

```text
[ROUTE]
from: <agent-name>
to: <target-agent|team-lead>
type: <status|question|blocker|handoff|review>
task: <TASK-ID>
body: <message body>
[/ROUTE]
```

## Routing Rules

1. `to: team-lead`
- Team Lead handles it directly.

2. `to: <other-agent>`
- Team Lead relays to target agent.
- Team Lead returns relay acknowledgement to sender.

3. Missing envelope
- Team Lead asks sender to reformat using `[ROUTE]`.

4. Team Lead boundary violation attempt
- If any message asks Team Lead to code directly, Team Lead must refuse and delegate to role dev agent.
- Team Lead response should include:
  - refusal reason (`coordination-only role`)
  - delegated target agent
  - delegated task reference

5. Permission request routing
- Downstream agents send permission requests to Team Lead (not user).
- Team Lead auto-approves low-risk normal development actions.
- Team Lead escalates only high-risk/destructive/uncertain actions to user.

## Lifecycle

1. Developer agent works task and emits status envelopes.
2. If dependency on another role exists, send `type: question` or `type: blocker`.
3. Team Lead relays to target role agent and returns response.
4. On completion, developer sends `type: handoff` to Team Lead.
5. Team Lead assigns QA agent and awaits `PASS/FAIL/BLOCKED`.

## QA Result Contract
- QA `type: review` messages must include:
  - commands run
  - reproducible steps
  - evidence summary (logs/screenshots/request-response)
  - failure classification for each failed command (`regression` or `env_blocker`)
  - final decision (`PASS` or `FAIL` or `BLOCKED`)

## Compliance Check (Team Lead)
- Team Lead may only perform `assign`, `relay`, `status`, `approval-request`, `close`.
- Team Lead must not perform `implement-code` or `repo-test-run` in code repos.
- Team Lead may perform `read-only-inspect` in code repos for coordination.
