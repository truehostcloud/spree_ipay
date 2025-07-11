# Configure Elastic APM
ElasticAPM.config do |config|
  config.service_name = 'spree_ipay_extension'
  config.server_url = 'http://localhost:8200'
  config.environment = Rails.env
  config.secret_token = 'development_secret_token' if Rails.env.development?
  config.api_request_time = 30
  config.api_request_size = 1024 * 1024
  config.log_level = :debug if Rails.env.development?
  config.transaction_sample_rate = 1.0 if Rails.env.development?
end

# Initialize Elastic APM
ElasticAPM.start

# Configure logging for iPay integration
module Spree
  module Ipay
    class Logger
      def self.debug(message, order_id = nil)
        transaction = ElasticAPM.start_transaction(name: "IPAY_DEBUG", type: "debug")
        transaction.set_label(:order_id, order_id) if order_id
        transaction.set_label(:message, message)
        transaction.set_label(:timestamp, Time.now)
        
        # Add custom metadata
        transaction.set_custom_context(
          payment_method: 'iPay',
          environment: Rails.env,
          version: Spree::Ipay::VERSION
        )
        transaction.end_transaction
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
