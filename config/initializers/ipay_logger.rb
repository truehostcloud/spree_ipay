# frozen_string_literal: true

# Configure the iPay logger
module Spree::Ipay
  module Logger
    SENSITIVE_KEYS = %i[number verification_value cvv card_number account_number iban].freeze
    
    def self.log_payment_event(message, data = {})
      # Log to standard Rails logger
      Rails.logger.info "[iPay] #{message}"
      Rails.logger.debug { "[iPay] Details: #{filter_sensitive_data(data).inspect}" } if data.present?
      
      # Also log to APM if available
      ApmLogger.log_payment_event(message, data) if defined?(ApmLogger)
    end

    def self.log_error(message, exception = nil)
      # Log to standard Rails logger
      Rails.logger.error "[iPay] ERROR: #{message}"
      if exception
        Rails.logger.error "[iPay] #{exception.class}: #{exception.message}"
        if Rails.env.development? || Rails.env.test?
          Rails.logger.error "[iPay] Backtrace: #{exception.backtrace.join("\n")}"
        end
      end
      
      # Also log to APM if available
      ApmLogger.log_error(message, exception) if defined?(ApmLogger)
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
    return {} unless data.is_a?(Hash)
    
    data.deep_dup.tap do |filtered|
      SENSITIVE_KEYS.each do |key|
        filtered[key] = '[FILTERED]' if filtered.key?(key)
      end
    end
  end
end

# Add a method to log payment events
module IpayLoggerHelper
  def log_payment_event(payment, event, details = {})
    details = {
      payment_id: payment.id,
      order_number: payment.order&.number,
      amount: payment.amount,
      currency: payment.currency,
      payment_method: payment.payment_method&.name,
      event: event
    }.merge(details)

    Spree::Ipay::Logger.log_payment_event("Payment #{event}", details)
  end

  def log_error(payment, error, context = {})
    details = {
      payment_id: payment&.id,
      order_number: payment&.order&.number,
      error: error.message,
      error_class: error.class.name
    }.merge(context)

    Spree::Ipay::Logger.log_error("Payment error: #{error.message}", error)
  end
end

# Include the helper in relevant classes
ActiveSupport.on_load(:action_controller) do
  include IpayLoggerHelper
end
