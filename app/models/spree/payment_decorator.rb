# frozen_string_literal: true

module Spree
  module PaymentDecorator
    def self.prepended(base)
      base.before_validation :ensure_payment_source, if: :ipay_payment?
      base.validates :source, presence: { message: 'must be present for iPay payments' }, if: :ipay_payment?
    end
    
    def ipay_payment?
      payment_method&.is_a?(Spree::PaymentMethod::Ipay)
    end
    
    def source_required?
      !(payment_method.respond_to?(:source_required?) && !payment_method.source_required?)
    end
    
    private
    
    def ensure_payment_source
      return false unless ipay_payment?
      
      # Use existing valid source if available
      if source.is_a?(Spree::IpaySource) && source.persisted?
        return source.valid?
      end
      
      # Get phone from source or order billing address
      phone = source&.phone.presence || order.bill_address&.phone.to_s.strip
      
      # Validate phone presence and format
      if phone.blank?
        errors.add(:base, 'Phone number is required for iPay payments')
        return false
      end
      
      # Normalize phone number (remove non-digits)
      phone = phone.gsub(/\D/, '')
      
      begin
        # Find or initialize payment source
        new_source = Spree::IpaySource.find_or_initialize_by(
          payment_method_id: payment_method_id,
          phone: phone
        )
        
        # Set additional attributes if new record
        if new_source.new_record?
          new_source.attributes = {
            user_id: order.user_id,
            status: 'pending'
          }
          
          unless new_source.save
            errors.add(:base, "Invalid payment details: #{new_source.errors.full_messages.to_sentence}")
            return false
          end
        end
        
        # Associate the source with payment
        self.source = new_source
        self.payment_method_id = payment_method_id
        true
        
      rescue ActiveRecord::RecordInvalid => e
        errors.add(:base, "Could not process payment: #{e.record.errors.full_messages.to_sentence}")
        false
      rescue => e
        errors.add(:base, 'An unexpected error occurred while processing your payment')
        Rails.logger.error("Payment processing error: #{e.message}\n#{e.backtrace.join("\n")}")
        false
      end
    end
  end
end

if defined?(Spree::Payment)
  Spree::Payment.prepend(Spree::PaymentDecorator)
end
