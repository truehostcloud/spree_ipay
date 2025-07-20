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
      Rails.logger.info("Payment##{id}: State changing from #{transition.from} to #{transition.to} for order #{order&.number}")
      Rails.logger.debug("Payment##{id}: Transition details: #{transition.inspect}")
    end
    
    def log_checkout_state
      Rails.logger.info("Payment##{id}: Reached checkout state for order #{order&.number}")
      Rails.logger.debug("Payment##{id}: Payment method: #{payment_method&.class&.name}, Source: #{source&.class&.name}")
    end
    
    def log_processing_state
      Rails.logger.info("Payment##{id}: Processing payment for order #{order&.number}")
      Rails.logger.debug("Payment##{id}: Amount: #{amount}, Response code: #{response_code}")
    end
    
    def log_pending_state
      Rails.logger.info("Payment##{id}: Payment pending for order #{order&.number}")
      Rails.logger.debug("Payment##{id}: Source state: #{source&.state if source.respond_to?(:state)}")
    end
    
    def log_completed_state
      Rails.logger.info("Payment##{id}: Payment completed for order #{order&.number}")
      Rails.logger.debug("Payment##{id}: Completed at: #{completed_at}, Updated at: #{updated_at}")
    end
    
    def log_failed_state
      Rails.logger.error("Payment##{id}: Payment failed for order #{order&.number}")
      Rails.logger.error("Payment##{id}: State changes: #{state_changes.inspect}")
    end
    
    def log_void_state
      Rails.logger.info("Payment##{id}: Payment voided for order #{order&.number}")
      Rails.logger.debug("Payment##{id}: Void details: #{response_code}")
    end
    
    private
    
    def log_payment_state(state_name)
      # No data logging
    end
    
    def ensure_payment_source
      Rails.logger.info("Payment##{id}: Ensuring payment source for iPay payment")
      
      return unless ipay_payment?
      
      if source.is_a?(Spree::IpaySource) && source.persisted?
        Rails.logger.info("Payment##{id}: Using existing iPay source ID: #{source.id}")
        return
      end
      
      # Log the current source state
      Rails.logger.debug("Payment##{id}: Current source: #{source.inspect}")
      Rails.logger.debug("Payment##{id}: Source attributes: #{source_attributes.inspect}")
      
      # Get phone from params or existing source
      phone = source_attributes.try(:[], :phone) || 
              source_attributes.try(:[], 'phone') ||
              (order.billing_address&.phone if order.billing_address.present?)
      
      Rails.logger.debug("Payment##{id}: Extracted phone: #{phone}")

      if phone.blank?
        error_msg = 'Phone number is required for iPay payments'
        Rails.logger.error("Payment##{id}: #{error_msg}")
        errors.add(:base, error_msg)
        return
      end
      
      # Clean and validate phone number
      phone_digits = phone.to_s.gsub(/\D/, '')
      if phone_digits.length != 10 && phone_digits.length != 12
        error_msg = 'Phone number must be 10 digits (e.g., 0700123456) or 12 digits (e.g., 254700123456)'
        Rails.logger.error("Payment##{id}: #{error_msg}")
        errors.add(:base, error_msg)
        return
      end
      
      # Convert to 254 format if needed
      phone_digits = "254#{phone_digits[1..-1]}" if phone_digits.length == 10 && phone_digits.start_with?('0')
      
      Rails.logger.info("Payment##{id}: Looking up or creating iPay source for phone: #{phone_digits}")

      # Create or find existing source
      new_source = Spree::IpaySource.find_or_initialize_by(
        payment_method_id: payment_method_id,
        phone: phone_digits
      )
      
      Rails.logger.debug("Payment##{id}: New source attributes: #{new_source.attributes}")

      if new_source.new_record?
        Rails.logger.info("Payment##{id}: Creating new iPay source")
        if new_source.save
          Rails.logger.info("Payment##{id}: Created new iPay source ID: #{new_source.id}")
        else
          error_msg = "Could not save payment source: #{new_source.errors.full_messages.to_sentence}"
          Rails.logger.error("Payment##{id}: #{error_msg}")
          errors.add(:base, error_msg)
          return
        end
      else
        Rails.logger.info("Payment##{id}: Found existing iPay source ID: #{new_source.id}")
      end

      # Associate the source with the payment
      Rails.logger.info("Payment##{id}: Associating source ID: #{new_source.id} with payment")
      self.source = new_source
      
      # Ensure the association is set
      if self.source != new_source
        Rails.logger.error("Payment##{id}: Failed to associate source with payment")
        errors.add(:base, 'Failed to associate payment source with payment')
        return
      end
      
      Rails.logger.info("Payment##{id}: Successfully associated source ID: #{new_source.id}")
      self.payment_method_id = payment_method_id
    end
  end
end

Spree::Payment.prepend(Spree::PaymentDecorator) if defined?(Spree::Payment)
