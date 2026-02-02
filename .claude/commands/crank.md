---
description: Turn the crank with Thicket
---

Your goal is to improve the project by resolving tickets and discovering additional work for future agents.

1. Work on the ticket described by `thicket ready`.
2. When it's ready, review your own code and resolve or file issues found.
3. Make sure that coverage is at least 90%.
4. When resolved, run `thicket close <CURRENT_TICKET_ID>`.
5. Think of additional work and create tickets for future agents:
   ```bash
   thicket add --title "Brief descriptive title" --description "Detailed context" --priority=<N> --type=<TYPE> --created-from <CURRENT_TICKET_ID>
   ```
6. Commit your changes, push to a branch with name es/... and create a PR.

**CRITICAL**: NEVER edit `.thicket/tickets.jsonl` directly. Always use the `thicket` CLI.