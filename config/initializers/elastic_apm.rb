# Initialize Elastic APM with configuration from YAML
ElasticAPM.start

# Configure logging for iPay integration
module Spree
  module Ipay
    class Logger
      def self.debug(message, order_id = nil)
        return unless (transaction = ElasticAPM.current_transaction)
        
        # Sanitize the message
        message = sanitize_message(message)
        
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
        Rails.logger.error "iPay Logger Error: #{e.message}"
      end

      def self.error(exception, order_id = nil)
        return unless (transaction = ElasticAPM.current_transaction)
        
        # Sanitize error message
        message = exception.is_a?(String) ? exception : exception.message
        sanitized_message = sanitize_message(message)
        
        # Add labels
        transaction.set_label(:order_id, order_id) if order_id
          
        context = {
          error_class: exception.is_a?(String) ? 'StandardError' : exception.class.name,
          message: sanitized_message,
          backtrace: exception.respond_to?(:backtrace) ? exception.backtrace.take(5) : nil,
          payment_method: 'iPay',
          environment: Rails.env,
          version: Spree::Ipay::VERSION
        }
        
        transaction.set_custom_context(context)
        ElasticAPM.report(exception, handled: false) if exception.is_a?(Exception)
      rescue => e
        Rails.logger.error "iPay Logger Error: #{e.message}"
      end

      private

      def self.sanitize_message(message)
        return message unless message.is_a?(String)
        
        # Mask phone numbers
        message = message.gsub(/(\+?[\d\s\-\(\)]{8,}\d)/) { |m| Spree::Ipay::DataMasking.mask_phone(m) }
        
        # Mask emails
        message = message.gsub(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i) { |m| Spree::Ipay::DataMasking.mask_email(m) }
        
        # Mask amounts (currency values)
        message = message.gsub(/\$\d+(\.\d{2})?/) { |m| "$#{Spree::Ipay::DataMasking.mask_amount(m.gsub(/\D/, ''))}" }
        
        # Mask credit card numbers
        message = message.gsub(/\b(?:\d[ -]*?){13,16}\b/) { |m| m.gsub(/\d(?=\d{4})/, '*') }
        
        message
      end
    end
  end
end
