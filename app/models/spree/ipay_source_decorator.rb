# frozen_string_literal: true

module Spree
  module IpaySourceDecorator
    def self.prepended(base)
      base.belongs_to :payment_method, class_name: 'Spree::PaymentMethod::Ipay', optional: true
      base.belongs_to :user, class_name: Spree.user_class.to_s, optional: true
      
      base.validates :phone, presence: true
      base.validates :phone, format: { with: /\A\+?\d{10,15}\z/, message: "must be a valid phone number" }, allow_blank: true
      
      base.before_validation :normalize_phone
    end
    
    private
    
    def normalize_phone
      return if phone.blank?
      
      # Remove any non-digit characters
      self.phone = phone.gsub(/\D/, '')
      
      # Add country code if missing (assuming Kenya +254)
      if phone.start_with?('0') && phone.length == 10
        self.phone = "254" + phone[1..-1]
      elsif phone.length == 9 && !phone.start_with?('0')
        self.phone = "254" + phone
      end
    end
  end
end

Spree::IpaySource.prepend(Spree::IpaySourceDecorator) if defined?(Spree::IpaySource)
