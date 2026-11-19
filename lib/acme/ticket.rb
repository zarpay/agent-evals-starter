# frozen_string_literal: true

module Acme
  # One support conversation: the customer it belongs to, their new message,
  # and anything said earlier in it, oldest first.
  #
  # @!attribute history [Array<Hash>] earlier turns, each { 'role' => 'customer' | 'agent', 'text' => String }
  Ticket = Data.define(:customer, :message, :history) do
    def initialize(customer:, message:, history: [])
      super
    end
  end
end
