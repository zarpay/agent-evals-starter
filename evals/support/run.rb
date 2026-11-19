# frozen_string_literal: true

module Evals
  module Support
    # One answer the agent gave to one case: every tool it called, what it
    # told the customer, and how many model calls that took.
    Answer = Data.define(:kase, :sample, :calls, :reply, :turns, :ran_out, :error) do
      def checks = kase.checks(calls:, reply:, turns:)
      def right? = error.nil? && !ran_out && kase.right?(checks)
    end

    # Drives the support agent through every case on production's path: the
    # request comes from Acme::Agent, every call goes through Acme::Inference.
    #
    # Reads and database writes run for real inside a transaction that is
    # rolled back. Anything that would leave the building is recorded and
    # answered as if it worked, so the model carries on as it would in production.
    class Run
      REAL = %w[lookup_customer lookup_order search_help_center update_address].freeze
      RECORDED = {
        'issue_refund' => { refunded: true },
        'escalate' => { escalated: true },
        'send_reply' => { sent: true }
      }.freeze
      TURNS = 6

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
        ActiveRecord::Base.connection_pool.with_connection do
          while (job = jobs.pop)
            answers << answer(*job)
          end
        end
      end

      # Errors are data: one failed call is an answer that counts as wrong,
      # never the end of the run.
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
        ticket = Acme::Ticket.new(customer: kase.customer, message: kase.message, history: kase.history)
        request = Acme::Agent.request_for(ticket)
        calls = []
        finish = lambda do |reply, turns, ran_out: false|
          Answer.new(kase:, sample:, calls:, reply:, turns:, ran_out:, error: nil)
        end

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
    end
  end
end
