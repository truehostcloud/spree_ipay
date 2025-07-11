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
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] payment_required? called. iPay payment: #{ipay_payment}, returning: #{result}")
      result
    end

    def confirmation_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      result = ipay_payment || super
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] confirmation_required? called. iPay payment: #{ipay_payment}, returning: #{result}")
      result
    end
    
    def log_before_confirm
      current_index = checkout_steps.index(state)
      next_step = current_index ? checkout_steps[current_index + 1] : 'unknown'
      
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Before confirm transition - State: #{state}")
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Checkout steps: #{checkout_steps.inspect}")
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Current step index: #{current_index}")
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Next step: #{next_step}")
    end
    
    def log_after_confirm
      current_index = checkout_steps.index(state)
      next_step = current_index ? checkout_steps[current_index + 1] : 'unknown'
      
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] After confirm transition - State: #{state}")
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Next step: #{next_step}")
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Payment state: #{payment_state}")
      payments.each do |payment|
        Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Payment #{payment.id} - State: #{payment.state}, Method: #{payment.payment_method&.type}")
      end
    end
    
    def log_complete_transition
      current_index = checkout_steps.index(state)
      
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Order completed!")
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Final state: #{state}, Payment state: #{payment_state}")
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Final checkout steps: #{checkout_steps.inspect}")
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Current step index: #{current_index}")
      
      payments.each do |payment|
        Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Final payment #{payment.id} - State: #{payment.state}, " \
                         "Method: #{payment.payment_method&.type}, Amount: #{payment.amount}")
      end
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
