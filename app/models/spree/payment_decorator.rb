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
      return unless ipay_payment?
      
      if source.is_a?(Spree::IpaySource) && source.persisted?
        return
      end
      
      # Get phone from params or existing source
      phone = source_attributes.try(:[], :phone) || 
              source_attributes.try(:[], 'phone') ||
              (order.billing_address&.phone if order.billing_address.present?)

      if phone.blank?
        errors.add(:base, 'Phone number is required for iPay payments')
        return
      end

      # Create or find existing source
      new_source = Spree::IpaySource.find_or_initialize_by(
        payment_method_id: payment_method_id,
        phone: phone
      )

      if new_source.new_record? && !new_source.save
        errors.add(:base, "Could not save payment source: #{new_source.errors.full_messages.to_sentence}")
        return
      end

      # Associate the source with the payment
      self.source = new_source
      self.payment_method_id = payment_method_id
    end
  end
end

Spree::Payment.prepend(Spree::PaymentDecorator) if defined?(Spree::Payment)
