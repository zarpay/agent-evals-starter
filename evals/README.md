# Evals

Each folder is one suite, with the same four files and a results folder: `cases.yml`, `case.rb`, `run.rb`, `report.rb`, `results/`. There's no base class. A new suite starts as a copy of the closest one.

| Suite | Measures | Task |
|---|---|---|
| `tagging/` | The tagger picks the one right topic for a message. One call, no tools: the warm-up. | `rake evals:tagging` |
| `support/` | The support agent calls the right tools in few turns, and does no more than policy allows. | `rake evals:support` |

Evals never run in CI: they call a real model, cost money and vary from run to run. Run one before and after any change to a prompt, a tool's name or description, the model, or the context the agent gets. Commit the report with the change. See [PLAYBOOK.md](../PLAYBOOK.md).
