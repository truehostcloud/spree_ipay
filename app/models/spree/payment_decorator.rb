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
      is_ipay = payment_method&.is_a?(Spree::PaymentMethod::Ipay)
      Spree::Ipay::SecureLogger.debug("Checking if iPay payment", order&.number, is_ipay: is_ipay)
      is_ipay
    end
    
    def source_required?
      required = !(payment_method.respond_to?(:source_required?) && !payment_method.source_required?)
      Spree::Ipay::SecureLogger.debug("Source required check", order&.number, source_required: required)
      required
    end
    
    def log_payment_state_change(transition)
      Spree::Ipay::SecureLogger.debug(
        "Payment state transition",
        order&.number,
        from_state: transition.from,
        to_state: transition.to,
        current_state: state,
        order_state: order&.state
      )
      
      if ipay_payment?
        Spree::Ipay::SecureLogger.debug(
          "iPay payment method details",
          order&.number,
          payment_method_type: payment_method&.class&.name,
          payment_method_id: payment_method&.id
        )
      end
    end
    
    def log_checkout_state
      log_payment_state('checkout')
    end
    
    def log_processing_state
      log_payment_state('processing')
      
      if ipay_payment? && order.confirmation_required?
        Spree::Ipay::Logger.debug("Order requires confirmation", order.number)
      end
    end
    
    def log_pending_state
      log_payment_state('pending')
    end
    
    def log_completed_state
      log_payment_state('completed')
      
      if ipay_payment?
        Spree::Ipay::SecureLogger.debug(
          "iPay payment completed",
          order.number,
          response_code_available: response_code.present?,
          avs_response_available: avs_response.present?
        )
      end
    end
    
    def log_failed_state
      log_payment_state('failed')
      
      if ipay_payment? && response_code.present?
        Spree::Ipay::SecureLogger.debug(
          "iPay payment failed",
          order.number,
          response_code_available: true
        )
      end
    end
    
    def log_void_state
      log_payment_state('void')
    end
    
    private
    
    def log_payment_state(state_name)
      Spree::Ipay::SecureLogger.debug("Now in #{state_name} state", order&.number)
      Spree::Ipay::SecureLogger.debug("Current amount: #{amount}, Captured amount: #{captured_amount}", order&.number)
      Spree::Ipay::SecureLogger.debug("State: #{state}", order&.number)
    end
    
    def ensure_payment_source
      return unless ipay_payment?
      return if source.present? && source.is_a?(Spree::IpaySource)
      
      Spree::Ipay::SecureLogger.debug("Ensuring iPay payment source", order.number)
      
      # Create a new source if one doesn't exist
      self.source ||= Spree::IpaySource.new
      
      # Set default values if needed
      if source.new_record?
        source.payment_method = payment_method
        source.user = order.user if order.respond_to?(:user)
        
        # Try to get phone from order billing address if available
        if order.bill_address.present? && order.bill_address.phone.present?
          source.phone = order.bill_address.phone
        end
        
        source.save!
        Spree::Ipay::SecureLogger.debug("Created new iPay source", order.number, source_id: source.id)
      end
    rescue StandardError => e
      Spree::Ipay::SecureLogger.error(e, order.number, error_class: e.class.name)
      raise e
      end

      # Associate the source with the payment
      self.source = new_source
      self.payment_method_id = payment_method_id
    end
  end
end

Spree::Payment.prepend(Spree::PaymentDecorator) if defined?(Spree::Payment)
