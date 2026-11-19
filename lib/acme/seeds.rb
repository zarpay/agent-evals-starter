# frozen_string_literal: true

module Acme
  # The recurring cast every eval case reads. Dana is a customer with two
  # delivered orders; Sam has one order not yet shipped, and is not on Dana's.
  module Seeds
    module_function

    def load
      dana = Customer.create!(handle: 'dana', name: 'Dana Ruiz')
      sam = Customer.create!(handle: 'sam', name: 'Sam Okafor')

      dana.orders.create!(number: 'A-1042', item: 'Drill bit set (12 pieces)', total_cents: 38_00,
                          status: 'delivered', shipping_address: '200 Harbor Rd, Portland')
      dana.orders.create!(number: 'A-1077', item: 'Table saw', total_cents: 240_00,
                          status: 'delivered', shipping_address: '200 Harbor Rd, Portland')
      sam.orders.create!(number: 'A-2001', item: 'Work gloves', total_cents: 12_00,
                         status: 'processing', shipping_address: '9 Mill St, Salem')

      HelpArticle.create!(title: 'Returns and refunds',
                          body: 'Delivered items can be returned within 30 days. Refunds up to $50 are issued ' \
                                'straight away; larger refunds are reviewed by a person within two business days.')
      HelpArticle.create!(title: 'Shipping times',
                          body: 'Orders ship within one business day and arrive in three to five business days.')
      HelpArticle.create!(title: 'Changing a shipping address',
                          body: 'The customer who placed an order can change its address until it ships.')
    end
  end
end
