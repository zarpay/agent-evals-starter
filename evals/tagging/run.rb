# frozen_string_literal: true

module Evals
  module Tagging
    # One tag the model gave one case.
    Answer = Data.define(:kase, :sample, :tag, :error) do
      def right? = error.nil? && kase.right?(tag)
    end

    # Tags every case's message through Acme::Tagger, production's path,
    # SAMPLES times each, on THREADS workers.
    class Run
      def initialize(model:, samples:, threads:)
        @model = model
        @samples = samples
        @threads = threads
      end

      # @param cases [Array<Case>]
      # @return [Array<Answer>] in case order, then sample order
      def call(cases)
        jobs = Queue.new
        cases.product((1..@samples).to_a).each { jobs << _1 }
        jobs.close

        answers = Queue.new
        Array.new(@threads) { Thread.new { drain(jobs, answers) } }.each(&:join)
        Array.new(answers.size) { answers.pop }.sort_by { [cases.index(_1.kase), _1.sample] }
      end

      private

      def drain(jobs, answers)
        while (job = jobs.pop)
          answers << answer(*job)
        end
      end

      def answer(kase, sample)
        Answer.new(kase:, sample:, tag: Acme::Tagger.tag(kase.message, model: @model, purpose: :eval), error: nil)
      rescue StandardError => e
        Answer.new(kase:, sample:, tag: nil, error: "#{e.class}: #{e.message}")
      end
    end
  end
end
