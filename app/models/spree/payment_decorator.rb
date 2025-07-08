# frozen_string_literal: true

module Spree
  module PaymentDecorator
    def self.prepended(base)
      Rails.logger.debug "OMKUU: Loading iPay payment decorator from gem"
      
      base.before_validation :ensure_payment_source, if: :ipay_payment?
      base.validates :source, presence: { message: 'must be present for iPay payments' }, if: :ipay_payment?
    end
    
    def ipay_payment?
      is_ipay = payment_method&.is_a?(Spree::PaymentMethod::Ipay)
      Rails.logger.debug "OMKUU: Checking if payment is iPay: #{is_ipay}"
      is_ipay
    end
    
    def source_required?
      required = !(payment_method.respond_to?(:source_required?) && !payment_method.source_required?)
      Rails.logger.debug "OMKUU: Source required for payment: #{required}"
      required
    end
    
    private
    
    def ensure_payment_source
      Rails.logger.debug "OMKUU: Ensuring payment source for iPay"
      return unless ipay_payment?
      
      if source.is_a?(Spree::IpaySource) && source.persisted?
        Rails.logger.debug "OMKUU: Using existing iPay source: #{source.id}"
      if phone.blank?
        errors.add(:base, :phone_required)
        return
      end
      
      new_source = Spree::IpaySource.find_or_initialize_by(payment_method_id: payment_method_id, phone: phone)
      
      if new_source.new_record?
        unless new_source.save
          errors.add(:base, "Could not save payment source: #{new_source.errors.full_messages.to_sentence}")
          return
        end
      end
      
      self.source = new_source
      self.payment_method_id = payment_method_id
    rescue => e
      Rails.logger.error "OMKUU ERROR in ensure_payment_source: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end
end

if defined?(Spree::Payment)
  Spree::Payment.prepend(Spree::PaymentDecorator)
  Rails.logger.debug "OMKUU: Successfully prepended PaymentDecorator"
else
  Rails.logger.error "OMKUU ERROR: Spree::Payment is not defined"
end
