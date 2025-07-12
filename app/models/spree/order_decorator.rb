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
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      result = ipay_payment ? false : super
      Spree::Ipay::Logger.debug("payment_required? called. iPay payment: #{ipay_payment}, returning: #{result}", number)
      Spree::Ipay::Logger.debug("Test log: iPay logging is working!", number)
      result
    end

    def confirmation_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      result = ipay_payment || super
      Spree::Ipay::Logger.debug("confirmation_required? called. iPay payment: #{ipay_payment}, returning: #{result}", number)
      result
    end
    
    def log_before_confirm
      current_index = checkout_steps.index(state)
      next_step = current_index ? checkout_steps[current_index + 1] : 'unknown'
      
      Spree::Ipay::Logger.debug("Before confirm transition - State: #{state}", number)
      Spree::Ipay::Logger.debug("Checkout steps: #{checkout_steps.inspect}", number)
      Spree::Ipay::Logger.debug("Current step index: #{current_index}", number)
      Spree::Ipay::Logger.debug("Next step: #{next_step}", number)
    end
    
    def log_after_confirm
      current_index = checkout_steps.index(state)
      next_step = current_index ? checkout_steps[current_index + 1] : 'unknown'
      
      Spree::Ipay::Logger.debug("After confirm transition - State: #{state}", number)
      Spree::Ipay::Logger.debug("Payment state: #{payment_state}", number)
      payments.each do |payment|
        Spree::Ipay::Logger.debug("Payment #{payment.id} - State: #{payment.state}, Method: #{payment.payment_method&.type}", number)
      end
    end
    
    def log_complete_transition
      current_index = checkout_steps.index(state)
      
      Spree::Ipay::Logger.debug("Order completed!", number)
      Spree::Ipay::Logger.debug("Final state: #{state}, Payment state: #{payment_state}", number)
      Spree::Ipay::Logger.debug("Final checkout steps: #{checkout_steps.inspect}", number)
      Spree::Ipay::Logger.debug("Current step index: #{current_index}", number)
      
      payments.each do |payment|
        Spree::Ipay::Logger.debug("[IPAY_DEBUG][Order-#{number}] Final payment #{payment.id} - State: #{payment.state}, " \
                         "Method: #{payment.payment_method&.type}, Amount: #{payment.amount}", number)
      end
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
