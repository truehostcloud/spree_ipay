# frozen_string_literal: true

module Spree
  module IpaySourceDecorator
    KENYAN_PHONE_REGEX = /\A254[17]\d{8}\z/ # Matches Kenyan phone numbers in international format
    
    def self.prepended(base)
      base.belongs_to :payment_method, 
                     class_name: 'Spree::PaymentMethod::Ipay', 
                     optional: true
                     
      base.belongs_to :user, 
                     class_name: Spree.user_class.to_s, 
                     optional: true
      
      base.validates :phone, 
                    presence: true,
                    format: { 
                      with: KENYAN_PHONE_REGEX, 
                      message: 'must be a valid Kenyan phone number (e.g., 254712345678)' 
                    }
      
      base.before_validation :normalize_phone
    end
    
    private
    
    def normalize_phone
      return if phone.blank?
      
      # Remove any non-digit characters and trim whitespace
      self.phone = phone.to_s.gsub(/\D/, '').strip
      
      # Handle Kenyan phone numbers
      case phone.length
      when 10
        # Convert local format (07XXXXXXXX) to international format (2547XXXXXXXX)
        self.phone = "254#{phone[1..-1]}" if phone.start_with?('0')
      when 9
        # Handle numbers without leading zero (7XXXXXXXX) by adding country code
        self.phone = "254#{phone}" if phone.match?(/\A[7-9]\d{8}\z/)
      end
      
      # Validate final format
      unless phone.match?(KENYAN_PHONE_REGEX)
        errors.add(:phone, 'must be a valid Kenyan phone number (e.g., 254712345678)')
      end
    rescue => e
      errors.add(:phone, 'could not be processed')
      Rails.logger.error("Phone normalization error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end
  end
end

if defined?(Spree::IpaySource)
  Spree::IpaySource.prepend Spree::IpaySourceDecorator
end
