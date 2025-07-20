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
      
      base.state_machine.before_transition(
        to: :complete,
        do: :before_complete
      )
      
      base.state_machine.after_transition(
        to: :complete,
        do: :log_complete_transition
      )
      
      # Add callback to reset state when order is modified
      base.before_update :reset_state_if_modified
    end

    def payment_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      ipay_payment ? false : super
    end

    def confirmation_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      ipay_payment || super
    end
    
    def log_before_confirm
      Rails.logger.info("Order #{number}: Before confirm state")
    end
    
    def log_after_confirm
      Rails.logger.info("Order #{number}: After confirm state")
    end
    
    def before_complete
      Rails.logger.info("Order #{number}: Before complete state")
      
      # If we're completing and have pending/processing payments, wait for them
      if payments.any? { |p| p.pending? || p.processing? }
        Rails.logger.warn("Order #{number}: Attempting to complete with pending/processing payments")
        return false
      end
      
      true
    end
    
    def log_complete_transition
      Rails.logger.info("Order #{number}: Completed successfully")
    end
    
    private
    
    def reset_state_if_modified
      # If we're in a state beyond address, check if line items have changed
      if %w[confirm complete].include?(state)
        # Check if any line items have been added, removed, or changed
        line_items_changed = line_items.any? do |line_item|
          line_item.changed? || line_item.new_record? || line_item.marked_for_destruction?
        end
        
        if line_items_changed
          self.state = 'payment'
          self.payment_state = 'balance_due'
          Rails.logger.info("Order #{number}: Reset to payment state due to modifications")
        end
      end
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
