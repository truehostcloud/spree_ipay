# frozen_string_literal: true

module Spree
  module IpaySourceDecorator
    def self.prepended(base)
      Rails.logger.debug "OMKUU: Setting up iPay source decorator"
      
      base.belongs_to :payment_method, class_name: 'Spree::PaymentMethod::Ipay', optional: true
      base.belongs_to :user, class_name: Spree.user_class.to_s, optional: true
      
      base.validates :phone, presence: true, format: { with: /\A\d{10,15}\z/, message: 'must be 10-15 digits' }
      
      base.before_validation :normalize_phone
    end
    
    private
    
    def normalize_phone
      Rails.logger.debug "OMKUU: Normalizing phone number: #{phone}"
      return if phone.blank?
      
      # Remove any non-digit characters
      self.phone = phone.gsub(/\D/, '')
      
      # Add country code if missing (assuming Kenya +254)
      if phone.start_with?('0') && phone.length == 10
        self.phone = "254" + phone[1..-1]
        Rails.logger.debug "OMKUU: Converted local number to international format: #{self.phone}"
      elsif phone.length == 9 && !phone.start_with?('0')
        self.phone = "254" + phone
        Rails.logger.debug "OMKUU: Added country code to number: #{self.phone}"
      end
      
      # Validate final format
      unless phone.match?(/\A254[17]\d{8}\z/)
        Rails.logger.warn "OMKUU: Invalid phone number format: #{phone}"
        errors.add(:phone, 'must be a valid Kenyan phone number (e.g., 254712345678)')
      end
    rescue => e
      Rails.logger.error "OMKUU ERROR: Error normalizing phone number: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end
end

if defined?(Spree::IpaySource)
  Spree::IpaySource.prepend Spree::IpaySourceDecorator
  Rails.logger.debug "OMKUU: Successfully prepended IpaySourceDecorator"
else
  Rails.logger.error "OMKUU ERROR: Spree::IpaySource is not defined"
end
