# frozen_string_literal: true

# Configure iPay payment method serialization
Rails.application.config.after_initialize do |app|
  Spree::Config.payment_methods_serializer = Spree::Config.payment_methods_serializer.merge(
    'Spree::PaymentMethod::Ipay' => 'Spree::IpaySource'
  )
end
