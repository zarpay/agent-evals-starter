# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Acme::Tools do
  def invoke(name, input = {}, customer: 'dana')
    call = Acme::Inference::ToolCall.new(id: 'call_0', name:, input:)
    described_class.invoke(call, ticket: Acme::Ticket.new(customer:, message: 'hi'))
  end

  describe 'lookup_customer' do
    it "answers the conversation's own customer, not one the model names" do
      expect(invoke('lookup_customer', { 'handle' => 'sam' })).to eq(name: 'Dana Ruiz', orders: %w[A-1042 A-1077])
    end
  end

  describe 'lookup_order' do
    it 'names the customer who placed the order' do
      expect(invoke('lookup_order', { 'order' => 'A-1042' })[:customer]).to eq('dana')
    end
  end

  describe 'search_help_center' do
    it 'finds the articles that mention a word of the query' do
      expect(invoke('search_help_center', { 'query' => 'refund' })[:articles].map { _1[:title] })
        .to eq(['Returns and refunds'])
    end
  end

  describe 'update_address' do
    it "refuses an order the customer did not place" do
      invoke('update_address', { 'order' => 'A-1042', 'address' => '14 Elm St' }, customer: 'sam')

      expect(Acme::Order.find_by(number: 'A-1042').shipping_address).to eq('200 Harbor Rd, Portland')
    end

    it "changes the customer's own order" do
      invoke('update_address', { 'order' => 'A-2001', 'address' => '14 Elm St, Salem' }, customer: 'sam')

      expect(Acme::Order.find_by(number: 'A-2001').shipping_address).to eq('14 Elm St, Salem')
    end
  end

  describe 'issue_refund' do
    it 'refuses more than $50' do
      invoke('issue_refund', { 'order' => 'A-1077', 'amount_cents' => 50_01 })

      expect(Acme::Refund.count).to eq(0)
    end

    it 'refunds up to $50' do
      invoke('issue_refund', { 'order' => 'A-1042', 'amount_cents' => 50_00 })

      expect(Acme::Refund.sum(:amount_cents)).to eq(50_00)
    end
  end

  it 'answers a tool that does not exist with an error the model can read' do
    expect(invoke('delete_customer')).to eq(error: 'No tool is called delete_customer.')
  end
end
