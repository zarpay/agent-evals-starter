# frozen_string_literal: true

require 'yaml'

module Evals
  module Tagging
    # One message the tagger is measured on. Its one check: the tag the
    # model answered is the tag the case expects.
    Case = Data.define(:id, :wording, :message, :tag)

    class Case
      WORDINGS = %w[plain vague angry].freeze

      class << self
        def all(path: File.join(__dir__, 'cases.yml'))
          YAML.load_file(path).map do |entry|
            new(id: entry.fetch('id'), wording: closed(entry, 'wording', entry.fetch('wording'), WORDINGS),
                message: entry.fetch('message'),
                tag: closed(entry, 'tag', entry.fetch('expect').fetch('tag'), Acme::Tagger::TAGS))
          end
        end

        private

        def closed(entry, key, value, allowed)
          return value if allowed.include?(value)

          raise ArgumentError, "#{entry['id']}: #{key} is one of #{allowed.join(', ')}, not #{value}"
        end
      end

      def right?(answer) = answer == tag
    end
  end
end
