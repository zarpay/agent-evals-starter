# frozen_string_literal: true

require 'fileutils'

module Evals
  module Tagging
    # One Markdown file per run, and the one-line summary the task prints:
    # overall, by expected tag, by wording, then every case not always
    # tagged right with each sample's answer.
    class Report
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

      def summary = "tagging · #{@model} · right #{rate(@answers)}"

      def markdown
        ["# tagging · #{@model} · #{@samples} samples · #{@at.strftime('%Y-%m-%dT%H%M')}", '',
         "**Right:** #{rate(@answers)} · **Errored:** #{@answers.count(&:error)}", '',
         breakdown('tag') { _1.kase.tag }, '', breakdown('wording') { _1.kase.wording }, '',
         *not_always_right].join("\n")
      end

      private

      def breakdown(name, &)
        "**By #{name}:** " + @answers.group_by(&).map { |value, answers| "#{value} #{rate(answers)}" }.join(' · ')
      end

      def not_always_right
        cases = @answers.group_by(&:kase).reject { |_, answers| answers.all?(&:right?) }
        return ['## Cases not always right', '', 'None.', ''] if cases.empty?

        ['## Cases not always right', '', *cases.flat_map do |kase, answers|
          ["### #{kase.id} · expected #{kase.tag}", '', "> #{kase.message}", '',
           *answers.map { "- #{_1.error ? "errored: #{_1.error}" : "answered #{_1.tag.inspect}"}" }, '']
        end]
      end

      def rate(answers)
        hits = answers.count(&:right?)
        "#{answers.empty? ? 0 : (100.0 * hits / answers.size).round}% (#{hits}/#{answers.size})"
      end
    end
  end
end
