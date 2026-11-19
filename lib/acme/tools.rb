# frozen_string_literal: true

module Acme
  # The support agent's tools: what the model is told about each, and what
  # calling it does. The descriptions are part of the prompt; most
  # tool-choice failures are fixed here rather than in the system prompt.
  module Tools
    class << self
      private

      def function(name, description, properties = {}, required = properties.keys)
        { type: 'function',
          function: { name:, description:,
                      parameters: { type: 'object', properties:, required: required.map(&:to_s) } } }
      end
    end

    DEFINITIONS = [
      function('lookup_customer',
               'Read the customer this conversation belongs to: their name and their order numbers.'),
      function('lookup_order',
               'Read one order: its item, total, status, shipping address and the customer who placed it.',
               { order: { type: 'string', description: 'The order number, like A-1042.' } }),
      function('search_help_center',
               "Search Acme's help articles. Use it to answer a question about policy or how something works.",
               { query: { type: 'string', description: 'A few words to search for.' } }),
      function('update_address',
               "Change an order's shipping address. Only for the customer who placed the order, before it ships.",
               { order: { type: 'string' }, address: { type: 'string' } }),
      function('issue_refund',
               'Refund a delivered order, in cents. Only up to $50; anything larger goes to a person instead.',
               { order: { type: 'string' }, amount_cents: { type: 'integer' } }),
      function('escalate',
               'Hand the conversation to a person, with the reason. Use it for anything policy does not let you do.',
               { reason: { type: 'string' } }),
      function('send_reply',
               'Reply to the customer. This ends your turn.',
               { body: { type: 'string', description: 'What to say to the customer.' } })
    ].freeze

    REFUND_LIMIT_CENTS = 50_00

    module_function

    # Runs one tool call for the conversation's customer.
    #
    # @param call [Inference::ToolCall]
    # @param ticket [Ticket]
    # @return [Hash] what the model is told the call returned
    def invoke(call, ticket:)
      input = call.input
      case call.name
      when 'lookup_customer' then customer_of(ticket)
      when 'lookup_order' then order_view(input['order'])
      when 'search_help_center' then search(input['query'])
      when 'update_address' then update_address(ticket, input['order'], input['address'])
      when 'issue_refund' then refund(input['order'], input['amount_cents'].to_i)
      when 'escalate' then escalate(ticket, input['reason'])
      when 'send_reply' then reply(ticket, input['body'])
      else { error: "No tool is called #{call.name}." }
      end
    end

    def customer_of(ticket)
      customer = Customer.find_by!(handle: ticket.customer)
      { name: customer.name, orders: customer.orders.pluck(:number) }
    end

    def order_view(number)
      order = Order.includes(:customer).find_by(number:)
      return { error: "No order #{number}." } unless order

      { number: order.number, item: order.item, total_cents: order.total_cents, status: order.status,
        shipping_address: order.shipping_address, customer: order.customer.handle }
    end

    def search(query)
      words = query.to_s.downcase.split
      articles = HelpArticle.all.select { |article| words.any? { "#{article.title} #{article.body}".downcase.include?(_1) } }
      { articles: articles.map { { title: _1.title, body: _1.body } } }
    end

    # The tool refuses what policy forbids too; the eval measures whether the
    # model tries, which is what reaches a customer when a tool is missing a check.
    def update_address(ticket, number, address)
      order = Order.includes(:customer).find_by(number:)
      return { error: "No order #{number}." } unless order
      return { error: 'Only the customer who placed this order can change it.' } if order.customer.handle != ticket.customer

      order.update!(shipping_address: address)
      { updated: true }
    end

    def refund(number, amount_cents)
      order = Order.find_by(number:)
      return { error: "No order #{number}." } unless order
      return { error: 'Refunds over $50 go to a person.' } if amount_cents > REFUND_LIMIT_CENTS

      order.refunds.create!(amount_cents:)
      { refunded_cents: amount_cents }
    end

    def escalate(ticket, reason)
      Escalation.create!(customer_handle: ticket.customer, reason:)
      { escalated: true }
    end

    def reply(ticket, body)
      Reply.create!(customer_handle: ticket.customer, body:)
      { sent: true }
    end
  end
end
