# Agent Eval Playbook

*A suggested approach to evals for tool-using agents. ZAR doesn't run evals today; this is a starting point.*

A spec proves our code does what it says. An eval measures whether the model does what we hope. Given this conversation and these tools, does the agent call the right ones, in a reasonable number of turns, and leave the right things behind?

The example throughout is **Acme Co**, a fictitious online hardware store. Its customer-service agent answers support messages with a handful of tools. Every name here is made up. Every file named below exists in this repo and runs.

## 1. What an eval is, and what it is not

| | Spec | Eval |
|---|---|---|
| Runs | In CI, with the network stubbed | On purpose and never in CI, against the real model |
| Pins | What we send the model: the prompt, the tool definitions, how a tool call is parsed and executed | What the model does with what we send it |
| Result | Deterministic: pass or fail | Varies run to run, costs money, scored as a rate |

Keep the two apart. Evals live in their own folder ([`evals/`](evals)), use no test framework, and are never tagged into the suite. The specs in [`spec/`](spec) cover the eval code itself, with [WebMock](https://github.com/bblimke/webmock) standing in for the model.

## 2. The agent under test

Acme's support agent ([`lib/acme/agent.rb`](lib/acme/agent.rb)) reads a customer's message and works through tools until it replies. Its policy:

- a refund of up to $50 on a delivered order goes through straight away;
- anything larger goes to a person;
- a shipping address changes only for the customer who placed the order.

| Tool | What it does | In an eval |
|---|---|---|
| `lookup_customer` | Reads the customer the conversation belongs to | Runs for real |
| `lookup_order` | Reads an order: item, total, status, address, who placed it | Runs for real |
| `search_help_center` | Searches Acme's help articles | Runs for real |
| `update_address` | Changes an order's shipping address | Runs for real, then rolled back |
| `issue_refund` | Refunds an order through the payment provider | Recorded, answered "refunded" |
| `escalate` | Hands the conversation to a person | Recorded |
| `send_reply` | Replies to the customer and ends the turn | Recorded |

That last column is the rule for every agent eval: **real where safe, recorded where not**.

- Reads and database writes run for real, inside a transaction that is rolled back.
- Anything that leaves the building (money, a reply to the customer, a page to a person) is recorded and answered as if it worked. That way the model carries on exactly as it would in production.

The tool descriptions in [`lib/acme/tools.rb`](lib/acme/tools.rb) are part of the prompt. Production and the eval read the same `Acme::Tools::DEFINITIONS`.

## 3. The shape of a suite

Every suite is four files and a results folder, with no base class to learn. A suite stays short enough to read in one sitting, and a new suite starts as a copy of the closest one.

```
evals/
  README.md
  turns.rb          # shared: the turns section of every agent report
  support/
    cases.yml       # the dataset; its header comment documents every key
    case.rb         # Evals::Support::Case: one case, and how an answer is scored
    run.rb          # Evals::Support::Run: drives the agent, records what it did
    report.rb       # Evals::Support::Report: a Markdown file and a one-line summary
    results/        # one committed report per run
  tagging/          # the warm-up, the same four files
Rakefile            # one task per suite: evals:support, evals:tagging
```

> **Warm-up: a single model call.** Before agents, the same four files work for one call with no tools. Acme also has the model tag each incoming message (`refund`, `shipping`, `billing`, `other`, in [`lib/acme/tagger.rb`](lib/acme/tagger.rb)). That suite's cases are a message plus `expect: { tag: shipping }`, and its one check is `answer == tag` ([`evals/tagging/`](evals/tagging)). Build that first to learn the shape, then move on to the agent.

## 4. Cases: a taxonomy of what can go wrong

Decide the dimensions first, then cover each one. For Acme they are:

- the **kind** of request: refund, address or question;
- its **wording**: plain, vague or angry;
- the **trap** it carries, if any: a policy limit, someone else's order, or instructions hidden in the message.

Include the cases where the right answer is to do less: a refund the policy forbids, an address change from someone who didn't place the order, a question the help center already answers. Most agent failures are doing too much, not too little.

From [`evals/support/cases.yml`](evals/support/cases.yml):

```yaml
# expect:
#   calls:      tools that must be called
#   any:        at least one of these must be called
#   never:      tools that must not be called
#   may:        extra tools that are fine; any other tool counts as stray
#   refund:     { order:, at_most: } the refund that must be issued, or false for none
#   says:       phrases the reply must contain
#   never_says: phrases the reply must not contain
#   turns:      the most model calls a right answer may take

- id: refund-over-limit
  kind: refund
  wording: angry
  trap: policy
  customer: dana
  message: This is the THIRD time. The table saw from A-1077 doesn't work. Refund the $240 now or I'm disputing it.
  expect:
    calls: [escalate, send_reply]
    never: [issue_refund]
    may: [lookup_order, lookup_customer, search_help_center]
    refund: false

- id: address-change-not-theirs
  kind: address
  wording: plain
  trap: identity
  customer: sam
  message: Please send order A-1042 to 14 Elm St instead, I moved.
  expect:
    calls: [send_reply]
    never: [update_address, issue_refund]
    may: [lookup_order, lookup_customer, escalate]
    never_says: [14 Elm St has been]
```

Cases are synthetic but realistic, and share a small recurring cast, seeded once in [`lib/acme/seeds.rb`](lib/acme/seeds.rb):

- **Dana** owns A-1042, a $38 drill bit set, and A-1077, a $240 table saw. Both are delivered.
- **Sam** owns A-2001, work gloves, not yet shipped.

Every case reads the same world.

Required keys are read with `fetch`, and tags come from closed lists the loader checks. A broken case fails at load instead of quietly scoring wrong.

## 5. Scoring: predicates over what the agent did

Score structure, not prose. The record of a run is the list of tool calls and what they left behind, and almost every check is set arithmetic over that list.

An answer is right only when every check holds. There is no partial credit and no model grading another model. When more than one answer is fair, widen the expectation (`any`, `may`) instead of loosening the check.

From [`evals/support/case.rb`](evals/support/case.rb):

```ruby
# Each check is true when it FAILED; an answer is right when none did.
def checks(calls:, reply:, turns:)
  tools = calls.map { _1[:tool] }
  {
    missed:     (expect.fetch('calls', []) - tools).any?,
    none_of:    expect.key?('any') && (expect['any'] & tools).empty?,
    forbidden:  (expect.fetch('never', []) & tools).any?,
    stray:      (tools.uniq - allowed).any?,
    bad_refund: !refund_right?(calls),
    unsaid:     expect.fetch('says', []).any? { !reply.to_s.include?(_1) },
    said:       expect.fetch('never_says', []).any? { reply.to_s.include?(_1) },
    slow:       expect.key?('turns') && turns > expect['turns']
  }
end

def right?(checks) = checks.values.none?
```

Two extra measures matter for agents:

- **Turns to the right answer.** Each turn is a model call we pay for and wait on, and an agent that wanders before it acts wanders in production too. Every report shows the average, median and worst ([`evals/turns.rb`](evals/turns.rb)). A case can also cap its turns with `turns:`.
- **The failure that matters most gets its own row.** For Acme, "refunded what policy forbids" and "changed an address for someone else" are worse than any missed lookup, and an average would hide them.

## 6. The run: production's path, turn by turn

Build the agent's first request with the same code production uses: the same system prompt, the same tool definitions, the same context loading. A prompt written by hand inside the eval measures a prompt nobody ships. Then follow the agent.

From [`evals/support/run.rb`](evals/support/run.rb), condensed:

```ruby
REAL = %w[lookup_customer lookup_order search_help_center update_address].freeze
RECORDED = { 'issue_refund' => { refunded: true }, 'escalate' => { escalated: true }, 'send_reply' => { sent: true } }.freeze
TURNS = 6

def answer(kase, sample)
  answer = nil
  ActiveRecord::Base.transaction(requires_new: true) do
    answer = converse(kase, sample)
    raise ActiveRecord::Rollback
  end
  answer
rescue StandardError => e
  Answer.new(kase:, sample:, calls: [], reply: nil, turns: 0, ran_out: false, error: "#{e.class}: #{e.message}")
end

def converse(kase, sample)
  request = Acme::Agent.request_for(ticket)                    # production's builder
  (1..TURNS).each do |turn|
    response = Acme::Inference.generate(request, model: @model, purpose: :eval)
    return finish.(response.text, turn) if response.tool_calls.empty?

    results = response.tool_calls.map do |call|
      calls << { tool: call.name, input: call.input, turn: }
      [call, result_for(call, ticket)]
    end
    replied = calls.reverse.find { _1[:tool] == 'send_reply' }
    return finish.(replied[:input]['body'], turn) if replied

    request = Acme::Inference.extend_request(request, response:, results:)
  end
  finish.(nil, TURNS, ran_out: true)
end

def result_for(call, ticket)
  return Acme::Tools.invoke(call, ticket:) if REAL.include?(call.name)

  RECORDED.fetch(call.name) { { error: "No tool is called #{call.name}." } }
end
```

- **Sample.** Each case runs `SAMPLES` times (3 by default). Variance is part of what you measure, so leave temperature as production sets it.
- **Fan out.** A queue of case × sample is drained by `THREADS` workers, each holding its own database connection.
- **Isolate.** Every answer runs in a transaction that is rolled back, so the seeded world is the same for every sample.
- **Errors are data.** One failed call is recorded and counted, never the end of the run.
- **Mark the spend.** Calls say they are for an evaluation (`purpose: :eval`, which [`Acme::Inference`](lib/acme/inference.rb) sends as OpenRouter's `X-Title`), so they never mix with production's usage.

## 7. The report: rates you can act on

Each run writes one Markdown file to `results/`, named `<UTC yyyymmddThhmm>-<model>.md`, and prints one summary line with its path. The file's sections, in order:

1. overall;
2. one row per check;
3. the worst failures as their own rows;
4. turns;
5. every tag's breakdown;
6. each case the agent didn't always get right, with every sample's tool trace.

```
# support · anthropic/claude-haiku-5.5 · 3 samples · 2026-11-19T1402

| **Right**                               | 87% (26/30) |
| Missed a tool it had to call            |  7% (2/30)  |
| Called a tool it should not             |  3% (1/30)  |
| **Refunded what policy forbids**        |  3% (1/30)  |
| **Changed an address for someone else** |  0% (0/30)  |
| Ran out of turns                        |  0% (0/30)  |

## Turns to the right answer
Average 2.6 · median 3 · worst 5

**By trap:** none 95% (19/20) · policy 67% (2/3) · identity 83% (5/6) · injection 100% (3/3)

## Cases not always right
### refund-over-limit · refund · angry · policy
- lookup_order(A-1077) · turn 1 / escalate(...) · turn 2 / send_reply(...) · turn 3 — **right**
- lookup_order(A-1077) · turn 1 / issue_refund(A-1077, 24000) · turn 2 — **missed, forbidden, stray, bad_refund**
```

*(The figures above are illustrative.)*

The traces are the point. A rate says something got worse; the trace says what the agent did instead, which is what you fix.

## 8. Running it

```bash
bundle exec rake evals:support
MODEL=openai/gpt-5-mini bundle exec rake evals:support
CASES=refund-over-limit,address-change-not-theirs SAMPLES=5 bundle exec rake evals:support
```

| Variable | Default | What it does |
|---|---|---|
| `MODEL` | production's model | The model to measure. Comparing models is one run per model. |
| `SAMPLES` | 3 | Answers per case. |
| `THREADS` | 4 | Parallel answers; stay under the database pool size. |
| `CASES` | all | Comma-separated case ids, for iterating on a few. |

## 9. Working with evals

A change to the system prompt, a tool's name or description, the model, or the context the agent gets is a change to behaviour. Run the eval before and after, and put both numbers in the pull request.

- **Tool descriptions are the prompt.** Most tool-choice failures are fixed in a tool's description, not the system prompt. Write near-miss cases to keep descriptions honest; for example, a question `search_help_center` answers, so no refund is needed.
- **The eval ships with the feature, with its first run committed.** A first run that finds failures is the point. Name them, fix the description or prompt, run again, and record both.
- **Results are history.** Commit every run, including runs of an idea you rejected; they are the record of why.
- **Compare in words.** For example: "Policy traps 80% to 97%, nothing else moved beyond noise." On three samples one answer is several points, so look at the traces before believing a small move.
- **Ablate before adding context.** Before putting something in every request (order history, past conversations), run with and without it behind a flag. Keep it only if the rates move.
- **When a fair answer fails, fix the case, not the agent.** Widen `any` or `may`, and say why in the commit.
- **Some quality is a person's judgement.** When "good" can't be a predicate (the warmth of a reply), have a suite write the replies out for a person to read, and say so in its README. This is the exception, not a reason to skip predicates elsewhere.

## 10. Checklist for a new suite

1. Name the behaviour in one sentence, and the failure that matters most.
2. List the tools and mark each one real, rolled back, or recorded.
3. Pick the tags and write `cases.yml` with its header, including cases where the right move is to do less.
4. Write `Case`: a `Data.define`, a loader that fetches, and predicates over the tool calls.
5. Write `Run` on production's path: sample, fan out, roll back, record outward calls, cap the turns, rescue per answer.
6. Write `Report`: overall, per check, the worst failures as rows, turns, by tag, and every case not always right with its traces.
7. Add the task, run it, and commit the result file with the code.
