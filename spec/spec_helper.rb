# frozen_string_literal: true

require 'tmpdir'
require 'webmock/rspec'
require_relative '../lib/acme'
require_relative '../evals/support/case'
require_relative '../evals/support/run'
require_relative '../evals/support/report'
require_relative '../evals/tagging/case'
require_relative '../evals/tagging/run'
require_relative '../evals/tagging/report'

ENV['OPENROUTER_API_KEY'] ||= 'test-key'
Acme::Database.connect(File.join(Dir.mktmpdir('acme'), 'test.sqlite3'))

# Specs pin the code and never reach a model: OpenRouter is the one network
# edge, and a spec that needs an answer from it says which.
module ModelAnswers
  def model_answers(*messages)
    stub_request(:post, Acme::Inference::URL.to_s)
      .to_return(*messages.map { { status: 200, body: { choices: [{ message: _1 }] }.to_json } })
  end

  def says(text) = { 'role' => 'assistant', 'content' => text }

  def calls(*tools)
    { 'role' => 'assistant', 'content' => nil,
      'tool_calls' => tools.each_with_index.map do |(name, input), i|
        { 'id' => "call_#{i}", 'type' => 'function', 'function' => { 'name' => name, 'arguments' => input.to_json } }
      end }
  end
end

RSpec.configure do |config|
  config.include ModelAnswers
  config.disable_monkey_patching!
  config.order = :random

  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
