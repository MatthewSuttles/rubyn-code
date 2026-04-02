# frozen_string_literal: true

module RubynCode
  module Permissions
    module Tier
      ASK_ALWAYS   = :ask_always
      ALLOW_READ   = :allow_read
      AUTONOMOUS   = :autonomous
      UNRESTRICTED = :unrestricted

      ALL = [ASK_ALWAYS, ALLOW_READ, AUTONOMOUS, UNRESTRICTED].freeze

      def self.all
        ALL
      end

      def self.valid?(tier)
        ALL.include?(tier)
      end
    end
  end
end
