# frozen_string_literal: true

module Acme
  # Tags an incoming support message with one topic, in a single call with no
  # tools: the warm-up the evals in evals/tagging measure.
  module Tagger
    TAGS = %w[refund shipping billing other].freeze

    INSTRUCTIONS = <<~TEXT
      Tag the customer's message with exactly one of: #{TAGS.join(', ')}.
      Answer with the tag alone, in lowercase.
    TEXT

    module_function

    # @return [Hash] the request, in OpenAI's chat format
    def request_for(message)
      { messages: [{ role: 'system', content: INSTRUCTIONS }, { role: 'user', content: message }] }
    end

    # @return [String] the tag the model answered, as it answered it
    def tag(message, model: Inference::DEFAULT_MODEL, purpose: :production)
      Inference.generate(request_for(message), model:, purpose:).text.to_s.strip.downcase
    end
  end
end
