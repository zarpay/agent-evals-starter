# frozen_string_literal: true

require 'active_record'
require 'json'
require 'net/http'

# Acme Co, an online hardware store whose support agent answers customer
# messages with a handful of tools. Fictitious and deliberately small: it
# exists so the evals in evals/ have a real agent to measure.
module Acme
  ROOT = File.expand_path('..', __dir__)
end

require_relative 'acme/database'
require_relative 'acme/models'
require_relative 'acme/seeds'
require_relative 'acme/ticket'
require_relative 'acme/inference'
require_relative 'acme/tools'
require_relative 'acme/agent'
require_relative 'acme/tagger'
