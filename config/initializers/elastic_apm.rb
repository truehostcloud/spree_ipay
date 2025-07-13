# Initialize Elastic APM with configuration from YAML
ElasticAPM.start if defined?(ElasticAPM)

module Spree
  module Ipay
    module ApmLogger
      def self.log_payment_event(message, data = {})
        return unless defined?(ElasticAPM)
        
        # Log basic event to APM with filtered data
        ElasticAPM.report_message(
          "iPay: #{message}",
          context: {
            custom: filter_sensitive_data(data)
          }
        )
      end

      def self.log_error(message, exception = nil)
        return unless defined?(ElasticAPM)
        
        if exception
          # Report the actual exception with sanitized backtrace
          ElasticAPM.report(exception) do |report|
            report.override_context(
              custom: {
                message: message,
                environment: Rails.env,
                timestamp: Time.now.iso8601
              }
            )
          end
        else
          # If no exception, just report a message
          ElasticAPM.report_message("iPay Error: #{message}")
        end
      end

      private

      def self.filter_sensitive_data(data)
        return {} unless data.is_a?(Hash)
        
        data.transform_values do |value|
          case value
          when Hash
            filter_sensitive_data(value)
          when String
            # Mask sensitive data in strings
            value.gsub(/\b\d{4,}\b/, '[FILTERED]')
          else
            value
          end
        end
      end
    end
  end
end
