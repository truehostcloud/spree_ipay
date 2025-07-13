# frozen_string_literal: true

# Configure the iPay logger
IpayLogger = if ENV['LOG_TO_STDOUT'].present?
               Logger.new(STDOUT)
             else
               Logger.new(Rails.root.join('log', 'ipay.log'))
             end

IpayLogger.level = if Rails.env.production?
                     Logger::INFO
                   else
                     Logger::DEBUG
                   end

IpayLogger.formatter = proc do |severity, datetime, _progname, msg|
  "[#{datetime.utc.iso8601}] #{severity}: #{msg}\n"
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
  helper_method :log_payment_event, :log_error
end
