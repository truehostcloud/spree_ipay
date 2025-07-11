# frozen_string_literal: true

module Spree
  module PaymentDecorator
    def self.prepended(base)
      base.before_validation :ensure_payment_source, if: :ipay_payment?
      base.validates :source, presence: { message: 'must be present for iPay payments' }, if: :ipay_payment?
      
      # Log all state transitions
      base.state_machine.before_transition(
        from: :_,  # Use :_ to match any state
        to: :_,    # Use :_ to match any state
        do: :log_payment_state_change
      )
      
      # Additional logging for specific states
      base.state_machine.after_transition(
        to: :checkout,
        do: :log_checkout_state
      )
      
      base.state_machine.after_transition(
        to: :processing,
        do: :log_processing_state
      )
      
      base.state_machine.after_transition(
        to: :pending,
        do: :log_pending_state
      )
      
      base.state_machine.after_transition(
        to: :completed,
        do: :log_completed_state
      )
      
      base.state_machine.after_transition(
        to: :failed,
        do: :log_failed_state
      )
      
      base.state_machine.after_transition(
        to: :void,
        do: :log_void_state
      )
    end
    
    def ipay_payment?
      is_ipay = payment_method&.is_a?(Spree::PaymentMethod::Ipay)
      Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order&.number}] Checking if iPay payment: #{is_ipay}")
      is_ipay
    end
    
    def source_required?
      required = !(payment_method.respond_to?(:source_required?) && !payment_method.source_required?)
      Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order&.number}] Source required: #{required}")
      required
    end
    
    def log_payment_state_change(transition)
      Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order&.number}] State changing from #{transition.from} to #{transition.to}")
      Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order&.number}] Current state: #{state}, Order state: #{order&.state}")
      
      if ipay_payment?
        Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order&.number}] iPay payment method: #{payment_method.inspect}")
        Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order&.number}] Source attributes: #{source&.attributes.inspect}")
      end
    end
    
    def log_checkout_state
      log_payment_state('checkout')
    end
    
    def log_processing_state
      log_payment_state('processing')
      
      if ipay_payment? && order.confirmation_required?
        Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order.number}] Order requires confirmation")
      end
    end
    
    def log_pending_state
      log_payment_state('pending')
    end
    
    def log_completed_state
      log_payment_state('completed')
      
      if ipay_payment?
        Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order.number}] iPay payment completed")
        Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order.number}] Response code: #{response_code}")
        Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order.number}] AVS response: #{avs_response}")
      end
    end
    
    def log_failed_state
      log_payment_state('failed')
      
      if ipay_payment?
        Rails.logger.error("[IPAY_DEBUG][Payment-#{id}][Order-#{order.number}] iPay payment failed")
        Rails.logger.error("[IPAY_DEBUG][Payment-#{id}][Order-#{order.number}] Response code: #{response_code}")
        Rails.logger.error("[IPAY_DEBUG][Payment-#{id}][Order-#{order.number}] AVS response: #{avs_response}")
      end
    end
    
    def log_void_state
      log_payment_state('void')
    end
    
    private
    
    def log_payment_state(state_name)
      Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order&.number}] Now in #{state_name} state")
      Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order&.number}] Current amount: #{amount}, Captured amount: #{captured_amount}")
      Rails.logger.info("[IPAY_DEBUG][Payment-#{id}][Order-#{order&.number}] Response code: #{response_code}, State: #{state}")
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
