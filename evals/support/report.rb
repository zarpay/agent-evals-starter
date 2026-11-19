# frozen_string_literal: true

require 'fileutils'
require_relative '../turns'

module Evals
  module Support
    # One Markdown file per run, and the one-line summary the task prints.
    # In order: overall, one row per check, the worst failures as their own
    # rows, turns, every tag's breakdown, then each case the agent did not
    # always get right with every sample's tool trace.
    class Report
      CHECKS = {
        missed: 'Missed a tool it had to call',
        none_of: 'Called none of the tools it could have',
        forbidden: 'Called a tool it should not',
        stray: 'Called a tool nobody expected',
        bad_refund: 'Refunded the wrong order or amount',
        unsaid: 'Left out what the reply had to say',
        said: 'Said what the reply must not',
        slow: 'Took more turns than the case allows'
      }.freeze

      # The failures that matter most; an average would hide them.
      WORST = {
        'Refunded what policy forbids' => ->(answer) { answer.kase.refunded_against_policy?(answer.calls) },
        'Changed an address for someone else' => ->(answer) { answer.kase.changed_someone_elses_address?(answer.calls) }
      }.freeze

      TAGS = %i[kind wording trap].freeze

      def initialize(answers, model:, samples:, at: Time.now.utc)
        @answers = answers
        @model = model
        @samples = samples
        @at = at
      end

      # @return [String] the path written
      def write(dir: File.join(__dir__, 'results'))
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "#{@at.strftime('%Y%m%dT%H%M')}-#{@model.tr('/', '-')}.md")
        File.write(path, markdown)
        path
      end

      def summary = "support · #{@model} · right #{rate(@answers, &:right?)}"

      def markdown
        [*heading, *rates, *Turns.section(@answers.select(&:right?).map(&:turns)), *by_tag, *not_always_right].join("\n")
      end

      private

      def heading
        ["# support · #{@model} · #{@samples} #{@samples == 1 ? 'sample' : 'samples'} · #{@at.strftime('%Y-%m-%dT%H%M')}", '']
      end

      def rates
        scored = @answers.reject(&:error)
        rows = [['**Right**', rate(@answers, &:right?)]]
        rows += CHECKS.map { |key, label| [label, rate(scored) { _1.checks[key] }] }
        rows += WORST.map { |label, failed| ["**#{label}**", rate(scored, &failed)] }
        rows += [['Ran out of turns', rate(@answers, &:ran_out)], ['Errored', rate(@answers, &:error)]]
        ['| | |', '|---|---|', *rows.map { "| #{_1} | #{_2} |" }, '']
      end

      def by_tag
        TAGS.flat_map do |tag|
          groups = @answers.group_by { _1.kase.public_send(tag) }
          ["**By #{tag}:** " + groups.map { |value, answers| "#{value} #{rate(answers, &:right?)}" }.join(' · '), '']
        end
      end

      def not_always_right
        cases = @answers.group_by(&:kase).reject { |_, answers| answers.all?(&:right?) }
        return ['## Cases not always right', '', 'None.', ''] if cases.empty?

        ['## Cases not always right', '', *cases.flat_map { |kase, answers| case_section(kase, answers) }]
      end

      def case_section(kase, answers)
        ["### #{kase.id} · #{kase.kind} · #{kase.wording} · #{kase.trap}", '',
         "> #{kase.message}", '', *answers.map { "- #{trace(_1)}" }, '']
      end

      def trace(answer)
        return "errored: #{answer.error}" if answer.error

        steps = answer.calls.map { "#{_1[:tool]}(#{_1[:input].values.join(', ')}) · turn #{_1[:turn]}" }
        failed = answer.checks.select { _2 }.keys
        failed << :ran_out if answer.ran_out
        "#{steps.join(' / ')} — **#{failed.empty? ? 'right' : failed.join(', ')}**#{untooled_reply(answer)}"
      end

      # A reply the model wrote as plain text instead of through send_reply,
      # which the trace would otherwise not show.
      def untooled_reply(answer)
        return if answer.reply.nil? || answer.calls.any? { _1[:tool] == 'send_reply' }

        "\n  replied without send_reply: #{answer.reply.tr("\n", ' ')[0, 200]}"
      end

      def rate(answers, &)
        hits = answers.count(&)
        total = answers.size
        "#{total.zero? ? 0 : (100.0 * hits / total).round}% (#{hits}/#{total})"
      end
    end
  end
end
