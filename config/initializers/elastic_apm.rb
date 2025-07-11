# Initialize Elastic APM with configuration from YAML
ElasticAPM.start

# Configure logging for iPay integration
module Spree
  module Ipay
    class Logger
      def self.debug(message, order_id = nil)
        transaction = ElasticAPM.current_transaction
        transaction.set_label(:order_id, order_id) if order_id
        transaction.set_label(:message, message)
        transaction.set_label(:timestamp, Time.now)
        
        # Add custom metadata
        transaction.set_custom_context(
          payment_method: 'iPay',
          environment: Rails.env,
          version: Spree::Ipay::VERSION
        )
      end

      def self.error(exception, order_id = nil)
        ElasticAPM.capture_exception(exception) do |report|
          report.set_label(:order_id, order_id) if order_id
          report.set_label(:timestamp, Time.now)
          
          # Add custom metadata
          report.set_custom_context(
            payment_method: 'iPay',
            environment: Rails.env,
            version: Spree::Ipay::VERSION
          )
        end
      end
    end
  end
end
