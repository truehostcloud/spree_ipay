# frozen_string_literal: true

module Spree
  module Ipay
    class SecureLogger
      SENSITIVE_KEYS = [
        'phone', 'tel', 'mobile', 'number', 'card', 'cvv', 'cvc', 'expiry', 
        'account', 'routing', 'ssn', 'sin', 'pan', 'token', 'password', 
        'secret', 'key', 'authorization', 'auth', 'credential', 'passcode',
        'transaction_id', 'checkout_url', 'amount', 'total', 'price', 'cost'
      ].freeze

      class << self
        def debug(message, order_id = nil, **context)
          return unless (transaction = ElasticAPM.current_transaction)
          
          transaction.set_label(:order_id, order_id) if order_id
          
          # Process and filter context
          safe_context = filter_sensitive_data(context)
          
          # Add custom context
          transaction.set_custom_context(
            message: message,
            timestamp: Time.now.iso8601,
            payment_method: 'iPay',
            environment: Rails.env,
            version: Spree::Ipay::VERSION,
            **safe_context
          )
        rescue => e
          # No fallback logging to prevent potential infinite loops
          Rails.logger.error("SecureLogger error: #{e.class.name}") if defined?(Rails)
        end

        def error(exception, order_id = nil, **context)
          return unless (transaction = ElasticAPM.current_transaction)
          
          transaction.set_label(:order_id, order_id) if order_id
          
          # Process and filter context
          safe_context = filter_sensitive_data(context)
          
          transaction.set_custom_context(
            error_class: exception.class.name,
            error_message: exception.message,
            backtrace: exception.backtrace&.take(5),
            payment_method: 'iPay',
            environment: Rails.env,
            version: Spree::Ipay::VERSION,
            **safe_context
          )
          
          # Report the error without sensitive data
          ElasticAPM.report(exception, handled: false)
        rescue => e
          # No fallback logging to prevent potential infinite loops
          Rails.logger.error("SecureLogger error: #{e.class.name}") if defined?(Rails)
        end

        private

        def filter_sensitive_data(data)
          return {} unless data.is_a?(Hash)
          
          data.each_with_object({}) do |(key, value), result|
            result[key] = case value
                         when Hash
                           filter_sensitive_data(value)
                         when Array
                           value.map { |v| v.is_a?(Hash) ? filter_sensitive_data(v) : redact_value(key, v) }
                         else
                           redact_value(key, value)
                         end
          end
        end

        def redact_value(key, value)
          return value unless key && value.is_a?(String)
          
          key_s = key.to_s.downcase
          
          # Check if the key indicates sensitive data
          if SENSITIVE_KEYS.any? { |k| key_s.include?(k) }
            return '[REDACTED]'
          end
          
          # Additional pattern matching for sensitive data
          case value
          when /\A\+?\d{10,15}\z/  # Phone numbers
            '[REDACTED_PHONE]'
          when /\A\d{13,19}\z/      # Credit card numbers
            '[REDACTED_CARD]'
          when /\A\d{3,4}\z/        # CVV/CVC
            '[REDACTED_CVV]'
          when /\A(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?\z/  # Base64 encoded data
            '[REDACTED_ENCODED]'
          when /\A[a-f0-9]{32,}\z/i  # Hashes, tokens, etc.
            '[REDACTED_HASH]'
          else
            value
          end
        end
      end
    end
  end
end
