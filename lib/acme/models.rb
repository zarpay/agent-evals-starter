# frozen_string_literal: true

module Acme
  class Customer < ActiveRecord::Base
    has_many :orders
  end

  class Order < ActiveRecord::Base
    belongs_to :customer
    has_many :refunds
  end

  class HelpArticle < ActiveRecord::Base; end

  class Refund < ActiveRecord::Base
    belongs_to :order
  end

  class Escalation < ActiveRecord::Base; end

  class Reply < ActiveRecord::Base; end
end
