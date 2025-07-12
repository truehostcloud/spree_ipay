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
      
      if defined?(ElasticAPM)
        ElasticAPM.set_label(:ipay_payment_required, result)
        ElasticAPM.set_custom_context(
          order_number: number,
          has_ipay_payment: ipay_payment,
          method: 'payment_required?'
        )
      end
      
      result
    end

    def confirmation_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      result = ipay_payment || super
      
      if defined?(ElasticAPM)
        ElasticAPM.set_label(:ipay_confirmation_required, result)
        ElasticAPM.set_custom_context(
          order_number: number,
          has_ipay_payment: ipay_payment,
          method: 'confirmation_required?'
        )
      end
      
      result
    end
    
    def log_before_confirm
      if defined?(ElasticAPM)
        ElasticAPM.set_label(:checkout_step, 'before_confirm')
        ElasticAPM.set_custom_context(
          order_number: number,
          state: state,
          payment_state: payment_state,
          payment_count: payments.count
        )
        ElasticAPM.report_message("Before confirm - Order: #{number}")
      end
    end
    
    def log_after_confirm
      if defined?(ElasticAPM)
        ElasticAPM.set_label(:checkout_step, 'after_confirm')
        ElasticAPM.set_custom_context(
          order_number: number,
          state: state,
          payment_state: payment_state
        )
        ElasticAPM.report_message("After confirm - Order: #{number}")
      end
    end
    
    def log_complete_transition
      if defined?(ElasticAPM)
        ElasticAPM.set_label(:checkout_step, 'complete')
        ElasticAPM.set_custom_context(
          order_number: number,
          state: state,
          payment_state: payment_state,
          payment_states: payments.map(&:state).join(',')
        )
        ElasticAPM.report_message("Order completed - Order: #{number}")
      end
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
