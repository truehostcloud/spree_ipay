# frozen_string_literal: true

# Configure the iPay logger
module Spree::Ipay::Logger
  SENSITIVE_KEYS = %i[number verification_value cvv card_number account_number iban].freeze
  
  def self.log_payment_event(message, data = {})
    logger.info "[iPay] #{message}"
    logger.debug { "[iPay] Details: #{filter_sensitive_data(data).inspect}" } if data.present?
  end

  def self.log_error(message, exception = nil)
    logger.error "[iPay] ERROR: #{message}"
    if exception
      logger.error "[iPay] #{exception.class}: #{exception.message}"
      # Only log full backtrace in development/test
      if Rails.env.development? || Rails.env.test?
        logger.error "[iPay] Backtrace: #{exception.backtrace.join("\n")}"
      end
    end
  end

  private

  def self.logger
    @logger ||= begin
      log_file = Rails.root.join('log', 'ipay.log')
      logger = ActiveSupport::Logger.new(log_file)
      logger.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime} [#{severity}] #{msg}\n"
      end
      logger.level = Rails.env.production? ? :info : :debug
      logger
    end
  end
  
  def self.filter_sensitive_data(data)
    return data unless data.is_a?(Hash)
    
    data.deep_dup.tap do |hash|
      hash.each do |key, value|
        if SENSITIVE_KEYS.include?(key.to_s.downcase.to_sym)
          hash[key] = '[FILTERED]'
        elsif value.is_a?(Hash)
          hash[key] = filter_sensitive_data(value)
        elsif value.is_a?(String) && key.to_s.downcase.include?('token')
          hash[key] = '[TOKEN]'
        end
      end
    end
  end
end

# Add a method to log payment events
module IpayLoggerHelper
  def log_payment_event(payment, event, details = {})
    log_data = {
      event: event,
      payment_id: payment.id,
      order_number: payment.order&.number,
      amount: payment.amount.to_f,
      currency: payment.currency,
      state: payment.state,
      details: details
    }
    
    IpayLogger.info(log_data.to_json)
  end
  
  def log_error(payment, error, context = {})
    log_data = {
      error: error.class.name,
      message: error.message,
      backtrace: Rails.env.development? ? error.backtrace.take(5) : nil,
      payment_id: payment&.id,
      order_number: payment&.order&.number,
      context: context
    }
    
    IpayLogger.error(log_data.to_json)
  end
end

# Include the helper in relevant classes
ActiveSupport.on_load(:action_controller) do
  include IpayLoggerHelper
end
