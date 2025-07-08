# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      base.has_many :ipay_sources, class_name: 'Spree::IpaySource', through: :payments, source: :source, source_type: 'Spree::IpaySource'
    end

    def payment_required?
      return false if payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      super
    end

    def confirmation_required?
      return true if payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      super
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
