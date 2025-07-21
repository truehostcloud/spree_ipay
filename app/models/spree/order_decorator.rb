# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      base.state_machine.before_transition(
        to: :confirm,
        do: :log_before_confirm
      )
      
      base.state_machine.after_transition(
        to: :confirm,
        do: :log_after_confirm
      )
      
      base.state_machine.after_transition(
        to: :complete,
        do: :log_complete_transition
      )
    end

    def payment_required?
      # Check if there are any iPay payments
      ipay_payments = payments.valid.select { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      
      # If no iPay payments, use default behavior
      return super if ipay_payments.empty?
      
      # Check if any iPay payment is completed or has a completed source
      ipay_payments.any? do |payment|
        payment.completed? || payment.source&.status == 'completed'
      end ? false : true
    end

    def confirmation_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      ipay_payment || super
    end
    
    # Override the next! method to prevent auto-completion for iPay orders
    def next(*args)
      # If payment is required but not completed, don't proceed
      if payment_required? && payment?
        ipay_payments = payments.valid.select { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
        
        # If there are iPay payments, check their status
        if ipay_payments.any?
          # Check if any iPay payment is completed or has a completed source
          valid_payment = ipay_payments.any? do |payment|
            payment.completed? || payment.source&.status == 'completed'
          end
          
          # If no valid payment, don't proceed
          return false unless valid_payment
        end
      end
      
      # Proceed with normal flow
      super
    end
    
    def log_before_confirm
      # No logging needed
    end
    
    def log_after_confirm
      # No logging needed
    end
    
    def log_complete_transition
      # No logging needed
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
