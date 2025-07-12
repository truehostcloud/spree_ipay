# frozen_string_literal: true

module Spree
  module PaymentDecorator
    def self.prepended(base)
      base.before_validation :ensure_payment_source, if: :ipay_payment?
      base.validates :source, presence: { message: 'must be present for iPay payments' }, if: :ipay_payment?
      
      # Log all state transitions
      states = base.state_machines[:state].states.map(&:name)
      states.each do |from_state|
        states.each do |to_state|
          next if from_state == to_state  # Skip transitions to same state
          
          base.state_machine.before_transition(
            from: from_state,
            to: to_state,
            do: :log_payment_state_change
          )
        end
      end
      
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
      payment_method&.is_a?(Spree::PaymentMethod::Ipay)
    end
    
    def source_required?
      !(payment_method.respond_to?(:source_required?) && !payment_method.source_required?)
    end
    
    def log_payment_state_change(transition)
      # No data logging
    end
    
    def log_checkout_state
      # No data logging
    end
    
    def log_processing_state
      # No data logging
    end
    
    def log_pending_state
      # No data logging
    end
    
    def log_completed_state
      # No data logging
    end
    
    def log_failed_state
      # No data logging
    end
    
    def log_void_state
      # No data logging
    end
    
    private
    
    def log_payment_state(state_name)
      # No data logging
    end
    
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
