# frozen_string_literal: true

module Spree
  module Ipay
    module DataMasking
      MASK = '[FILTERED]'.freeze

      def self.mask_phone(phone)
        return MASK unless phone.present?
        # Keep last 2 digits, mask the rest
        phone.to_s.gsub(/\d(?=\d{2})/, '*')
      end

      def self.mask_email(email)
        return MASK unless email.present?
        # Keep first letter, domain and TLD
        email.to_s.gsub(/(?<=.).(?=.*@)/, '*')
      end

      def self.mask_amount(amount)
        return MASK unless amount.present?
        amount.to_s.gsub(/\d/, '*')
      end

      def self.mask_transaction_id(id)
        return MASK unless id.present?
        id.length > 8 ? "#{id[0..3]}****#{id[-4..-1]}" : id
      end

      def self.sanitize_hash(hash, sensitive_keys = %w[phone email amount response_code])
        return MASK unless hash.respond_to?(:transform_values)
        
        hash.transform_values do |value|
          if value.is_a?(Hash)
            sanitize_hash(value, sensitive_keys)
          elsif value.respond_to?(:downcase) && sensitive_keys.any? { |k| k.downcase == value.to_s.downcase }
            MASK
          else
            value
          end
        end
      end
    end
  end
end
