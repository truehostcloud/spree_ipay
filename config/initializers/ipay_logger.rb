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
  filtered_msg = msg.to_s.dup
  
  # Filter out common sensitive data patterns
  [
    # Payment data
    /(?:card[_-]?number|account[_-]?number|cc[_-]?num|ccn)[\s=:]+([\w-]+)/i,
    /(?:cvv|cvc|cvv2|security[_-]?code)[\s=:]+([\w-]+)/i,
    /(?:expir(?:y|ation)[_-]?(?:date)?|exp[_-]?date)[\s=:]+([\w\/]+)/i,
    /(?:exp[_-]?(?:month|mon|m))[\s=:]+(\d{1,2})/i,
    /(?:exp[_-]?(?:year|yr|y))[\s=:]+(\d{2,4})/i,
    /(?:amount|amt|total)[\s=:]+([\d.,]+)/i,
    
    # Personal data
    /(?:phone|mobile|tel)[\s=:]+([\d\s+\-()]+)/,
    /(?:ssn|social[_-]?security[_-]?(?:number|num|no|#)?)[\s=:]+([\w-]+)/i,
    /(?:tax[_-]?id|tax[_-]?number|tin)[\s=:]+([\w-]+)/i,
    /(?:dob|date[_-]?of[_-]?birth)[\s=:]+([\d\/\-]+)/i,
    
    # Authentication
    /(?:password|passwd|pwd|pass)[\s=:]+([^\s\n]+)/i,
    /(?:api[_-]?key|access[_-]?token|secret[_-]?key|auth[_-]?token)[\s=:]+([\w-]+)/i,
    /(?:refresh[_-]?token|session[_-]?(?:id|token))[\s=:]+([\w-]+)/i,
    /(?:authorization)[\s:]+(?:basic|bearer)[\s]+([\w=.-]+)/i,
    
    # URLs with tokens
    /([&?](?:token|key|auth|secret|password|access_token|refresh_token|api_key)=)[^&\s]+/i
  ].each do |pattern|
    filtered_msg.gsub!(pattern, '\1[FILTERED]')
  end
  
  # Filter JSON values
  filtered_msg.gsub!(/"(?:card_number|account_number|ccn|cvv|cvc|expiry|expiration_date|phone|ssn|tax_id|api_key|token|secret|password|auth_token)"\s*:\s*"([^"]+)"/i, '"\1":"[FILTERED]"')
  
  # Filter XML values
  filtered_msg.gsub!(/<(?:CardNumber|AccountNumber|CVV|ExpirationDate|Phone|SSN|TaxID|ApiKey|Token|Secret|Password|AuthToken)[^>]*>([^<]+)<\/\w+>/i, '<\1>[FILTERED]</\1>')
  
  # Log format
  "[#{datetime.utc.iso8601}] #{severity}: #{filtered_msg}\n"
end

# Add a method to log payment events safely
module IpayLoggerHelper
  def log_payment_event(payment, event, _details = {})
    # Minimal logging - only event type and payment ID
    log_data = {
      event: event,
      payment_id: payment.id
    }
    
    IpayLogger.info(log_data.to_json)
  end
  
end

# Include the helper in relevant classes
ActiveSupport.on_load(:action_controller) do
  include IpayLoggerHelper
  helper_method :log_payment_event
end
