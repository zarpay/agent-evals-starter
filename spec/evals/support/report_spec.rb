# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Evals::Support::Report do
  let(:kase) { Evals::Support::Case.all.find { _1.id == 'refund-over-limit' } }

  def answer(*tools)
    Evals::Support::Answer.new(kase:, sample: 1, calls: tools.map { { tool: _1, input: {}, turn: 1 } },
                               reply: 'ok', turns: 2, ran_out: false, error: nil)
  end

  def report = described_class.new([answer('escalate', 'send_reply'), answer('issue_refund', 'send_reply')],
                                   model: 'test/model', samples: 2)

  it 'gives the worst failure its own row' do
    expect(report.markdown).to include('| **Refunded what policy forbids** | 50% (1/2) |')
  end

  it 'traces every sample of a case not always right' do
    expect(report.markdown).to include('issue_refund() · turn 1 / send_reply() · turn 1 — **missed, forbidden, stray, bad_refund**')
  end

  it 'writes the report under the model and time it was run' do
    path = described_class.new([], model: 'test/model', samples: 1, at: Time.utc(2026, 11, 19, 14, 2))
                          .write(dir: Dir.mktmpdir)

    expect(File.basename(path)).to eq('20261119T1402-test-model.md')
  end
end
