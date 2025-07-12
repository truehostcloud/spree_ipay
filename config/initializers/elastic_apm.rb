# Configure Elastic APM with security in mind
# This initializer is loaded automatically by Rails

# Define a safe logger wrapper that won't fail if ElasticAPM is not available
module Spree::Ipay
  module_function

  def logger
    @logger ||= if defined?(ElasticAPM) && ElasticAPM.running?
      # If ElasticAPM is available, use it with our secure logger
      require_relative '../../app/services/spree/ipay/secure_logger' unless defined?(Spree::Ipay::SecureLogger)
      Spree::Ipay::SecureLogger
    else
      # Fallback to Rails logger if ElasticAPM is not available
      Rails.logger
    end
  rescue => e
    # If anything goes wrong, use a null logger
    require 'logger'
    @logger = Logger.new(nil)
  end
end

# Start ElasticAPM if it's available
if defined?(ElasticAPM)
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
    
    # Disable collection of sensitive data
    capture_headers: false,
    custom_key_filters: [/password/i, /secret/i, /token/i],
    
    # Disable SQL query collection
    enabled_environments: ['production', 'staging'],
    enabled_injectors: %i[net_http httpclient],
    sql_sanitizer: :safely,
    
    # Disable collection of SQL queries
    span_frames_min_duration: '5ms',
    stack_trace_limit: 10,
    transaction_max_spans: 50,
    transaction_sample_rate: 1.0,
    
    # Disable collection of SQL queries
    verify_server_cert: true
  )
end

# Configure logging for iPay integration using SecureLogger
module Spree
  module Ipay
    # @deprecated Use Spree::Ipay::SecureLogger instead
    class Logger
      def self.debug(message, order_id = nil, **context)
        ::Spree::Ipay::SecureLogger.debug(message, order_id, **context)
      end

      def self.error(exception, order_id = nil, **context)
        ::Spree::Ipay::SecureLogger.error(exception, order_id, **context)
      end
    end
  end
end
