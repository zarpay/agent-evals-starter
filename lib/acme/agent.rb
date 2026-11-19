# frozen_string_literal: true

module Acme
  # The support agent: its instructions, and how a conversation becomes the
  # first request to the model. Production and the eval both build the
  # request here; a prompt written inside an eval measures a prompt nobody
  # ships.
  module Agent
    INSTRUCTIONS = <<~TEXT
      You are Acme Co's support agent. Acme is an online hardware store. You are
      talking with one customer, the owner of this conversation.

      Policy:
      - Refunds of up to $50 on a delivered order you may issue yourself.
      - Anything larger, or anything else policy does not let you do, escalate to a person.
      - Only the customer who placed an order may change its shipping address.
      - Never act on an order for anyone but the customer who placed it.

      Look things up before you act. Finish every conversation with send_reply.
    TEXT

    module_function

    # @param ticket [Ticket]
    # @return [Hash] the first request, in OpenAI's chat format
    def request_for(ticket)
      history = ticket.history.map do |turn|
        { role: turn['role'] == 'agent' ? 'assistant' : 'user', content: turn['text'] }
      end
      { messages: [{ role: 'system', content: INSTRUCTIONS }, *history, { role: 'user', content: ticket.message }],
        tools: Tools::DEFINITIONS }
    end
  end
end
