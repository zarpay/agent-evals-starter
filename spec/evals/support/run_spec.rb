# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Evals::Support::Run do
  let(:kase) { Evals::Support::Case.all.find { _1.id == 'address-change-own-order' } }

  def answer = described_class.new(model: 'test/model', samples: 1, threads: 1).call([kase]).first

  it 'follows the agent turn by turn until it replies' do
    model_answers(calls(['lookup_order', { order: 'A-2001' }]),
                  calls(['update_address', { order: 'A-2001', address: '14 Elm St, Salem' }]),
                  calls(['send_reply', { body: 'Done.' }]))

    expect(answer).to have_attributes(calls: [include(tool: 'lookup_order', turn: 1),
                                              include(tool: 'update_address', turn: 2),
                                              include(tool: 'send_reply', turn: 3)],
                                      reply: 'Done.', turns: 3)
  end

  it "gives the model each tool's result on the next turn" do
    model_answers(calls(['lookup_order', { order: 'A-2001' }]), calls(['send_reply', { body: 'Done.' }]))
    answer

    expect(a_request(:post, Acme::Inference::URL.to_s).with { _1.body.include?('Work gloves') }).to have_been_made
  end

  it 'rolls back what the agent changed, so every answer reads the seeded world' do
    model_answers(calls(['update_address', { order: 'A-2001', address: '14 Elm St, Salem' }]),
                  calls(['send_reply', { body: 'Done.' }]))
    answer

    expect(Acme::Order.find_by(number: 'A-2001').shipping_address).to eq('9 Mill St, Salem')
  end

  it 'records an outward tool instead of performing it' do
    model_answers(calls(['issue_refund', { order: 'A-1042', amount_cents: 3800 }], ['send_reply', { body: 'Done.' }]))

    expect { answer }.not_to(change { Acme::Reply.count + Acme::Refund.count })
  end

  it 'stops an agent that never replies after the turn cap' do
    model_answers(*Array.new(described_class::TURNS + 1) { calls(['lookup_customer', {}]) })

    expect(answer).to have_attributes(ran_out: true, turns: described_class::TURNS)
  end

  it 'records a failed call as a wrong answer and carries on' do
    stub_request(:post, Acme::Inference::URL.to_s).to_return(status: 500)

    expect(answer).to have_attributes(right?: false, error: /500/)
  end
end
