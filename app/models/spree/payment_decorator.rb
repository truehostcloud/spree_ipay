# frozen_string_literal: true

module Spree
  module PaymentDecorator
    def self.prepended(base)
      base.before_validation :ensure_payment_source, if: :ipay_payment?
      base.before_validation :invalidate_previous_payments, if: :ipay_payment?
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
    
    # Invalidates any previous pending or processing payments for this order
    def invalidate_previous_payments
      return unless order && (pending? || checkout?)
      
      Rails.logger.info "omkuu: ====== STARTING PAYMENT INVALIDATION ======"
      Rails.logger.info "omkuu: Order: #{order.number}, Current payment ID: #{id || 'nil'}, State: #{state}"
      
      # Get all payments for this order with the same payment method
      all_payments = order.payments
                        .where(payment_method: payment_method)
                        .order(created_at: :desc)
      
      # Log all payments for debugging
      Rails.logger.info "omkuu: All payments for order #{order.number}:"
      all_payments.each do |p|
        Rails.logger.info "omkuu: - Payment ID: #{p.id}, State: #{p.state}, Amount: #{p.amount}, Created: #{p.created_at}, Updated: #{p.updated_at}"
      end
      
      # Find payments to invalidate (exclude current payment and already invalid/voided ones)
      payments_to_invalidate = all_payments.reject do |p| 
        (id.present? && p.id == id) || p.void? || p.state == 'invalid' || p.state == 'completed' || p.state == 'failed'
      end
      
      Rails.logger.info "omkuu: Found #{payments_to_invalidate.count} payments to invalidate"
      
      if payments_to_invalidate.empty?
        Rails.logger.info "omkuu: No payments to invalidate"
        return
      end
      
      payments_to_invalidate.each do |payment|
        begin
          Rails.logger.info "omkuu: ====== PROCESSING PAYMENT #{payment.id} ======"
          Rails.logger.info "omkuu: Current state: #{payment.state}, Amount: #{payment.amount}"
          
          # Double check state before processing
          if payment.void? || payment.state == 'invalid' || payment.state == 'completed'
            Rails.logger.info "omkuu: Payment #{payment.id} already in final state: #{payment.state}, skipping"
            next
          end
          
          # Void the transaction if not already voided
          unless payment.void?
            Rails.logger.info "omkuu: Voiding payment #{payment.id}"
            payment.void_transaction!
          end
          
          # Update payment state to invalid
          Rails.logger.info "omkuu: Marking payment #{payment.id} as invalid"
          result = payment.update_columns(
            state: 'invalid',
            updated_at: Time.current
          )
          
          if result
            Rails.logger.info "omkuu: Successfully invalidated payment #{payment.id}"
          else
            Rails.logger.error "omkuu: Failed to update payment #{payment.id} - #{payment.errors.full_messages.join(', ')}"
          end
          
        rescue StandardError => e
          Rails.logger.error "omkuu: ERROR processing payment #{payment.id}: #{e.class} - #{e.message}"
          Rails.logger.error "omkuu: Backtrace: #{e.backtrace.first(5).join("\n")}"
        end
      end
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
