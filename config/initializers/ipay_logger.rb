# frozen_string_literal: true

# Configure the iPay logger to filter sensitive data
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

# Configure log formatter to filter sensitive data
IpayLogger.formatter = proc do |severity, datetime, _progname, msg|
  filtered_msg = msg.dup
  
  # Filter out sensitive data patterns
  filtered_msg.gsub!(/number\s*=>\s*[\"\'][^\"\']*[\"\']/i, 'number=>[FILTERED]')
  filtered_msg.gsub!(/card_?number\s*=>\s*[\"\'][^\"\']*[\"\']/i, 'card_number=>[FILTERED]')
  filtered_msg.gsub!(/cvv\s*=>\s*[\"\'][^\"\']*[\"\']/i, 'cvv=>[FILTERED]')
  filtered_msg.gsub!(/amount\s*=>\s*[\"\'][^\"\']*[\"\']/i, 'amount=>[FILTERED]')
  filtered_msg.gsub!(/currency\s*=>\s*[\"\'][^\"\']*[\"\']/i, 'currency=>[FILTERED]')
  
  "[#{datetime.utc.iso8601}] #{severity}: #{filtered_msg}\n"
end

# Add a method to log payment events safely
module IpayLoggerHelper
  def log_payment_event(payment, event, details = {})
    # Only log non-sensitive data
    log_data = {
      event: event,
      payment_id: payment.id,
      order_number: payment.order&.number,
      state: payment.state
    }
    
    # Only include non-sensitive details
    if details.present?
      log_data[:details] = details.except(
        :card_number, :cvv, :amount, :currency,
        :account_number, :routing_number, :bank_account_number
      )
    end
    
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
