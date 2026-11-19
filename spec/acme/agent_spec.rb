# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Acme::Agent do
  it "puts earlier turns between the instructions and the customer's new message, in the model's roles" do
    ticket = Acme::Ticket.new(customer: 'dana', message: 'The drill bits.',
                              history: [{ 'role' => 'customer', 'text' => 'It broke.' },
                                        { 'role' => 'agent', 'text' => 'Which order?' }])

    expect(described_class.request_for(ticket)[:messages].drop(1))
      .to eq([{ role: 'user', content: 'It broke.' }, { role: 'assistant', content: 'Which order?' },
              { role: 'user', content: 'The drill bits.' }])
  end
end
