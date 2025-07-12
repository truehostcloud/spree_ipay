# Configure Elastic APM with security in mind
ElasticAPM.start(
  # Security settings
  filter_parameters: [
    'password', 'secret', 'token', 'authorization', 'api_key', 'api-key',
    'card[number]', 'card[cvv]', 'card[expiry]', 'card[exp_month]', 'card[exp_year]',
    'cc_number', 'cc_cvv', 'cc_exp', 'cc_exp_month', 'cc_exp_year',
    'account_number', 'routing_number', 'ssn', 'sin', 'pan', 'cvv', 'cvc'
  ],
  
  # Sanitize field names
  sanitize_field_names: [
    'password', 'passwd', 'pwd', 'secret', 'api_key', 'api-key', 'token',
    'card[number]', 'card[cvv]', 'card[expiry]', 'card[exp_month]', 'card[exp_year]',
    'cc_number', 'cc_cvv', 'cc_exp', 'cc_exp_month', 'cc_exp_year',
    'account_number', 'routing_number', 'ssn', 'sin', 'pan', 'cvv', 'cvc',
    'phone', 'mobile', 'tel', 'number', 'contact', 'email', 'address'
  ],
  
  # Disable potentially sensitive data collection
  capture_body: 'errors',
  transaction_max_spans: 50,
  stack_trace_limit: 10,
  
  # Application settings
  app_name: 'Spree iPay',
  environment: Rails.env,
  log_level: ENV['ELASTIC_APM_LOG_LEVEL'] || 'info',
  
  # Disable potentially sensitive data
  capture_headers: false,
  capture_environment: false,
  
  # Disable SQL query capture as it might contain sensitive data
  enabled_environments: Rails.env.production? ? ['production'] : ['development', 'test']
)

# Configure logging for iPay integration using SecureLogger
module Spree
  module Ipay
    # @deprecated Use Spree::Ipay::SecureLogger instead
    class Logger
      def self.debug(message, order_id = nil, **context)
        SecureLogger.debug(message, order_id, **context)
      end

      def self.error(exception, order_id = nil, **context)
        SecureLogger.error(exception, order_id, **context)
      end
    end
    
    # Alias for backward compatibility
    SecureLogger = ::Spree::Ipay::SecureLogger unless defined?(::Spree::Ipay::SecureLogger)
  end
end
