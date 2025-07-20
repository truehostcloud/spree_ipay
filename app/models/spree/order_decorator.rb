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
      # Always require payment, even for iPay
      true
    end

    def confirmation_required?
      # Only require confirmation for non-iPay payments
      !payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
    end
    
    def log_before_confirm
      Rails.logger.info("IPAY_DEBUG: Order[#{number}]: Before confirm state")
    end
    
    def log_after_confirm
      Rails.logger.info("IPAY_DEBUG: Order[#{number}]: After confirm state")
    end
    
    def before_complete
      Rails.logger.info("IPAY_DEBUG: Order[#{number}]: Before complete state")
      
      # For iPay payments, ensure we have a completed payment
      if payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
        Rails.logger.info("IPAY_DEBUG: Order[#{number}]: Checking iPay payment status")
        Rails.logger.info("IPAY_DEBUG: Order[#{number}]: Payments: #{payments.map { |p| "#{p.number}:#{p.state}" }.join(', ')}")
        
        unless payments.completed.any? || payments.pending.any? || payments.processing.any?
          Rails.logger.warn("IPAY_DEBUG: Order[#{number}]: Blocking completion - no valid iPay payment found")
          return false
        end
      else
        # For non-iPay payments, use standard behavior
        if payments.any? { |p| p.pending? || p.processing? }
          Rails.logger.warn("IPAY_DEBUG: Order[#{number}]: Blocking completion - pending/processing payments")
          return false
        end
      end
      
      Rails.logger.info("IPAY_DEBUG: Order[#{number}]: Payment validation passed")
      true
    end
    
    def log_complete_transition
      Rails.logger.info("IPAY_DEBUG: Order[#{number}]: Successfully completed")
    end
    
    private
    
    def reset_state_if_modified
      # Only reset if we're in confirm or complete state
      return unless %w[confirm complete].include?(state)
      
      # Check if any line items have been added, removed, or changed
      line_items_changed = line_items.any? do |line_item|
        line_item.changed? || line_item.new_record? || line_item.marked_for_destruction?
      end
      
      # Also check if any line items were removed through nested attributes
      line_items_removed = line_items.any?(&:_destroy)
      
      if line_items_changed || line_items_removed
        Rails.logger.info("IPAY_DEBUG: Order[#{number}]: Detected changes - Line items changed: #{line_items_changed}, " \
                         "Line items removed: #{line_items_removed}")
        
        self.state = 'payment'
        self.payment_state = 'balance_due'
        
        # Invalidate any existing payments
        payments.incomplete.each do |payment|
          if payment.can_invalidate?
            Rails.logger.info("IPAY_DEBUG: Order[#{number}]: Invalidating payment #{payment.number}")
            payment.invalidate!
          end
        end
        
        Rails.logger.info("IPAY_DEBUG: Order[#{number}]: Reset to payment state")
        true
      else
        Rails.logger.debug("IPAY_DEBUG: Order[#{number}]: No line item changes detected")
        false
      end
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
