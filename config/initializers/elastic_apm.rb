# Initialize Elastic APM with configuration from YAML
ElasticAPM.start

# Configure logging for iPay integration
module Spree
  module Ipay
    class Logger
      def self.debug(message, order_id = nil)
        return unless (transaction = ElasticAPM.current_transaction)
        
        # Add labels
        transaction.set_label(:order_id, order_id) if order_id
        
        # Add custom context
        context = {
          message: message,
          timestamp: Time.now.iso8601,
          payment_method: 'iPay',
          environment: Rails.env,
          version: Spree::Ipay::VERSION
        }
        
        transaction.set_custom_context(context)
      rescue => e
# Fallback logging removed since we're handling errors differently
      end

      def self.error(exception, order_id = nil)
        # Add context to current transaction if it exists
        if (transaction = ElasticAPM.current_transaction)
          transaction.set_label(:order_id, order_id) if order_id
          
          context = {
            error_class: exception.class.name,
            backtrace: exception.backtrace.take(5),
            payment_method: 'iPay',
            environment: Rails.env,
            version: Spree::Ipay::VERSION
          }
          
          transaction.set_custom_context(context)
        end
        
        # Report the error
        ElasticAPM.report(exception, handled: false)
      rescue => e
# Fallback logging removed since we're handling errors differently
      end
    end
  end
end
