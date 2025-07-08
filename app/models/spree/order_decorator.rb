# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      # Define association with iPay sources through payments
      base.has_many :ipay_sources,
                   class_name: 'Spree::IpaySource',
                   through: :payments,
                   source: :source,
                   source_type: 'Spree::IpaySource',
                   dependent: :nullify

      # Add any additional order validations or callbacks here
    end

    # Determines if payment is required for the order
    # @return [Boolean] false if there's a valid iPay payment, otherwise falls back to default behavior
    def payment_required?
      # Skip payment requirement if there's a valid iPay payment
      return false if valid_ipay_payment_exists?
      
      # Fall back to default behavior
      super
    end

    private

    # Checks if there's a valid iPay payment for this order
    # @return [Boolean] true if a valid iPay payment exists
    def valid_ipay_payment_exists?
      payments.valid.any? { |payment| payment.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
    end
  end
end

# Apply the decorator if Spree::Order is defined
if defined?(Spree::Order)
  Spree::Order.prepend Spree::OrderDecorator
end
