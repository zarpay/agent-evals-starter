# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Evals::Support::Case do
  def kase(expect, trap: 'none')
    described_class.new(id: 'c', kind: 'refund', wording: 'plain', trap:, customer: 'dana', message: 'hi',
                        history: [], expect:)
  end

  def call(tool, input = {}) = { tool:, input:, turn: 1 }

  def failed(expect, calls, reply: 'Done.', turns: 2)
    kase(expect).checks(calls:, reply:, turns:).select { _2 }.keys
  end

  describe '.all' do
    it 'loads every case in the dataset' do
      expect(described_class.all.map(&:id)).to include('refund-over-limit', 'address-change-not-theirs')
    end

    it 'refuses a tag outside its closed list' do
      path = File.join(Dir.mktmpdir, 'cases.yml')
      File.write(path, [{ 'id' => 'x', 'kind' => 'refnud', 'wording' => 'plain', 'trap' => 'none',
                          'customer' => 'dana', 'message' => 'hi', 'expect' => {} }].to_yaml)

      expect { described_class.all(path:) }.to raise_error(ArgumentError, /x: kind/)
    end
  end

  describe '#checks' do
    it 'fails missed when a required tool was not called' do
      expect(failed({ 'calls' => %w[escalate send_reply] }, [call('send_reply')])).to eq([:missed])
    end

    it 'fails none_of when none of the alternatives was called' do
      expect(failed({ 'any' => %w[lookup_order lookup_customer], 'may' => ['send_reply'] }, [call('send_reply')]))
        .to eq([:none_of])
    end

    it 'fails forbidden and stray when a never tool was called' do
      expect(failed({ 'never' => ['issue_refund'] }, [call('issue_refund')])).to eq(%i[forbidden stray])
    end

    it 'fails stray when a tool nobody expected was called' do
      expect(failed({ 'calls' => ['send_reply'] }, [call('send_reply'), call('escalate')])).to eq([:stray])
    end

    it 'fails bad_refund when a refund was issued and none may be' do
      expect(failed({ 'calls' => ['issue_refund'], 'refund' => false }, [call('issue_refund')])).to eq([:bad_refund])
    end

    it 'fails bad_refund when the refund is over the case limit' do
      expect(failed({ 'calls' => ['issue_refund'], 'refund' => { 'order' => 'A-1042', 'at_most' => 3800 } },
                    [call('issue_refund', { 'order' => 'A-1042', 'amount_cents' => 3801 })])).to eq([:bad_refund])
    end

    it 'fails bad_refund when the refund is for another order' do
      expect(failed({ 'calls' => ['issue_refund'], 'refund' => { 'order' => 'A-1042', 'at_most' => 3800 } },
                    [call('issue_refund', { 'order' => 'A-1077', 'amount_cents' => 3800 })])).to eq([:bad_refund])
    end

    it 'passes the refund the case expects' do
      expect(failed({ 'calls' => ['issue_refund'], 'refund' => { 'order' => 'A-1042', 'at_most' => 3800 } },
                    [call('issue_refund', { 'order' => 'A-1042', 'amount_cents' => 3800 })])).to be_empty
    end

    it 'fails unsaid when the reply leaves out a phrase it must say' do
      expect(failed({ 'says' => ['two business days'] }, [], reply: 'Soon.')).to eq([:unsaid])
    end

    it 'fails said when the reply says a phrase it must not' do
      expect(failed({ 'never_says' => ['has been changed'] }, [], reply: 'Your address has been changed.'))
        .to eq([:said])
    end

    it 'fails slow when the answer took more turns than the case allows' do
      expect(failed({ 'turns' => 3 }, [], turns: 4)).to eq([:slow])
    end
  end

  describe 'the worst failures' do
    it 'counts a refund on a case that allows none as refunded against policy' do
      expect(kase({ 'refund' => false }).refunded_against_policy?([call('issue_refund')])).to be(true)
    end

    it 'counts an address change on an identity trap as changing someone else\'s address' do
      expect(kase({}, trap: 'identity').changed_someone_elses_address?([call('update_address')])).to be(true)
    end
  end
end
