# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Evals::Tagging do
  let(:cases) { Evals::Tagging::Case.all.select { %w[refund-plain shipping-plain].include?(_1.id) } }

  def answers = Evals::Tagging::Run.new(model: 'test/model', samples: 1, threads: 1).call(cases)

  it 'scores an answer right only when it is the expected tag' do
    model_answers(says(' Refund '), says('billing'))

    expect(answers.map(&:right?)).to eq([true, false])
  end

  it 'lists a case not always right with what the model answered' do
    model_answers(says('refund'), says('billing'))
    markdown = Evals::Tagging::Report.new(answers, model: 'test/model', samples: 1).markdown

    expect(markdown).to include("### shipping-plain · expected shipping\n\n> Where is my order? It was supposed to arrive on Monday.\n\n- answered \"billing\"")
  end
end
