# Agent evals starter

A small, runnable example of measuring a tool-using agent: does it call the right tools, in a reasonable number of turns, and take the right actions?

The agent is **Acme Co's customer-service agent**. Acme is a fictitious online hardware store and everything in it is made up. It is small enough to read in one sitting, and real enough that the evals measure something. Copy the shape, not the company.

[PLAYBOOK.md](PLAYBOOK.md) is the suggested approach: what an eval is, how to build one, and how to work with it. This file is the quick start.

## Quick start

```bash
bundle install
bundle exec rspec                  # the specs: no model, no network, runs in CI

export OPENROUTER_API_KEY=...      # evals call a real model and cost money
bundle exec rake evals:tagging     # the warm-up: one call, no tools
bundle exec rake evals:support     # the agent
```

Each eval prints one line and writes a Markdown report to its `results/` folder:

```
support · anthropic/claude-haiku-5.5 · right 87% (26/30) · evals/support/results/20261119T1402-anthropic-claude-haiku-5.5.md
```

| Variable | Default | What it does |
|---|---|---|
| `MODEL` | production's (`ACME_MODEL`, else `anthropic/claude-haiku-5.5`) | The OpenRouter model to measure. Comparing models is one run per model. |
| `SAMPLES` | 3 | Answers per case. |
| `THREADS` | 4 | Answers in parallel; stays under the database pool. |
| `CASES` | all | Comma-separated case ids, for iterating on a few. |

```bash
MODEL=openai/gpt-5-mini bundle exec rake evals:support
CASES=refund-over-limit,address-change-not-theirs SAMPLES=5 bundle exec rake evals:support
```

## What's where

```
lib/acme/            the app: models, seeds, tools, the agent, and Inference, its one seam to a model
evals/
  turns.rb           the turns section every agent report carries
  tagging/           the warm-up suite: one call, no tools
  support/           the agent suite
    cases.yml        the dataset; its header documents every key
    case.rb          one case, and how an answer is scored
    run.rb           drives the agent on production's path and records what it did
    report.rb        the Markdown report and the summary line
    results/         one committed report per run
spec/                specs for the code above; WebMock stands in for the model
```

`bundle exec rake db:reset` deletes the local SQLite database; the next run creates and seeds it again.
