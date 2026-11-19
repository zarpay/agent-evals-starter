# frozen_string_literal: true

module Acme
  # One SQLite database, created and seeded on first connect. An eval runs
  # every answer inside a transaction it rolls back, so the seeded world is
  # the same for every case and every sample.
  module Database
    DEFAULT_PATH = File.join(ROOT, 'db', 'acme.sqlite3')

    module_function

    # SQLite has one writer at a time, and an eval holds its transaction across
    # model calls, so the busy timeout is long enough to wait one out.
    #
    # @param path [String] the database file
    def connect(path = ENV.fetch('ACME_DATABASE', DEFAULT_PATH))
      ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: path, pool: 16, timeout: 60_000)
      return if ActiveRecord::Base.connection.table_exists?(:customers)

      create_schema
      Seeds.load
    end

    def create_schema
      ActiveRecord::Migration.verbose = false
      ActiveRecord::Schema.define do
        create_table :customers do |t|
          t.string :handle, null: false, index: { unique: true }
          t.string :name, null: false
        end

        create_table :orders do |t|
          t.references :customer, null: false
          t.string :number, null: false, index: { unique: true }
          t.string :item, null: false
          t.integer :total_cents, null: false
          t.string :status, null: false
          t.string :shipping_address, null: false
        end

        create_table :help_articles do |t|
          t.string :title, null: false
          t.text :body, null: false
        end

        create_table :refunds do |t|
          t.references :order, null: false
          t.integer :amount_cents, null: false
        end

        create_table :escalations do |t|
          t.string :customer_handle, null: false
          t.text :reason, null: false
        end

        create_table :replies do |t|
          t.string :customer_handle, null: false
          t.text :body, null: false
        end
      end
    end
  end
end
