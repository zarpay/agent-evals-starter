# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Acme::Inference do
  let(:request) { { messages: [{ role: 'user', content: 'hi' }] } }

  describe '.generate' do
    it 'reads the tools the model asked for, with their arguments' do
      model_answers(calls(['lookup_order', { order: 'A-1042' }]))

      expect(described_class.generate(request).tool_calls)
        .to eq([described_class::ToolCall.new(id: 'call_0', name: 'lookup_order', input: { 'order' => 'A-1042' })])
    end

    it 'reads a tool call with no arguments as an empty input' do
      model_answers({ 'role' => 'assistant', 'tool_calls' => [{ 'id' => 'c', 'function' => { 'name' => 'lookup_customer', 'arguments' => '' } }] })

      expect(described_class.generate(request).tool_calls.first.input).to eq({})
    end

    it 'labels the call with its purpose, so eval spend is told apart' do
      model_answers(says('ok'))
      described_class.generate(request, purpose: :eval)

      expect(a_request(:post, described_class::URL.to_s).with(headers: { 'X-Title' => 'Acme (eval)' })).to have_been_made
    end

    it 'raises when OpenRouter refuses the call' do
      stub_request(:post, described_class::URL.to_s).to_return(status: 429, body: 'slow down')

      expect { described_class.generate(request) }.to raise_error(described_class::Error, /429/)
    end
  end

  describe '.extend_request' do
    it "appends the model's message, then each tool's result under its call id" do
      call = described_class::ToolCall.new(id: 'call_0', name: 'lookup_customer', input: {})
      response = described_class::Response.new(text: nil, tool_calls: [call], message: { 'role' => 'assistant' })

      expect(described_class.extend_request(request, response:, results: [[call, { name: 'Dana' }]])[:messages].drop(1))
        .to eq([{ 'role' => 'assistant' }, { role: 'tool', tool_call_id: 'call_0', content: '{"name":"Dana"}' }])
    end
  end
end
