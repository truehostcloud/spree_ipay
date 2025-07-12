# Initialize Elastic APM with configuration from YAML
ElasticAPM.start if defined?(ElasticAPM)

# Configure minimal logging for iPay integration
module Spree
  module Ipay
    class Logger
      def self.debug(_message, _order_id = nil)
        # No-op to prevent any data from being logged
      end

      def self.error(exception, _order_id = nil)
        # Only report the error class and a generic message without sensitive data
        return unless defined?(ElasticAPM)
        
        # Create a sanitized exception with minimal information
        safe_exception = StandardError.new("Payment processing error")
        safe_exception.set_backtrace([])
        
        # Report the sanitized error
        ElasticAPM.report(safe_exception, handled: true) do |report|
          # Set a generic error type without exposing actual error details
          report.override_context(
            custom: {
              error_type: exception.class.name,
              environment: Rails.env,
              timestamp: Time.now.iso8601
            }
          )
        end
      rescue => e
        # No fallback logging to prevent data leakage
      end
    end
  end
end
