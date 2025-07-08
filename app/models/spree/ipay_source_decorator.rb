# frozen_string_literal: true

module Spree
  module IpaySourceDecorator
    def self.prepended(base)
      Rails.logger.debug "OMKUU: Loading iPay source decorator from gem"
      
      base.belongs_to :payment_method, class_name: 'Spree::PaymentMethod::Ipay', optional: true
      base.belongs_to :user, class_name: Spree.user_class.to_s, optional: true
      
      base.validates :phone, presence: true
      base.validates :phone, format: { with: /\A\+?\d{10,15}\z/, message: "must be a valid phone number" }, allow_blank: true
      
      base.before_validation :normalize_phone
    end
    
    private
    
    def normalize_phone
      return if phone.blank?
      
      Rails.logger.debug "OMKUU: Normalizing phone number: #{phone}"
      
      # Remove any non-digit characters
      self.phone = phone.gsub(/\D/, '')
      
      # Add country code if missing (assuming Kenya +254)
      if phone.start_with?('0') && phone.length == 10
        self.phone = "254" + phone[1..-1]
        Rails.logger.debug "OMKUU: Updated phone with country code: #{self.phone}"
      elsif phone.length == 9 && !phone.start_with?('0')
        self.phone = "254" + phone
        Rails.logger.debug "OMKUU: Added country code to phone: #{self.phone}"
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
