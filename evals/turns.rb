# frozen_string_literal: true

module Evals
  # The turns section every agent eval's report carries: how many turns the
  # right answers took. Fewer is better: each turn is a model call, paid for
  # and waited on, and an agent that wanders before it acts wanders in
  # production too.
  module Turns
    module_function

    # @param counts [Array<Integer>] turns each right answer took
    # @return [Array<String>] Markdown lines
    def section(counts)
      return ['## Turns to the right answer', '', 'No right answers.', ''] if counts.empty?

      sorted = counts.sort
      median = sorted[sorted.size / 2]
      histogram = sorted.tally.map { |turns, n| "| #{turns} | #{'█' * n} #{n} |" }
      ['## Turns to the right answer', '',
       "Average #{(counts.sum.to_f / counts.size).round(1)} · median #{median} · worst #{sorted.last}", '',
       '| Turns | Answers |', '|---|---|', *histogram, '']
    end
  end
end
