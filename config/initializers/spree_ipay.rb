# frozen_string_literal: true

# Configure iPay payment method serialization for Spree 4.10.1+
Rails.application.config.after_initialize do |app|
  # For Spree 4.10.1, we'll use the class_eval approach to add the serializer
  Spree::Api::V2::Platform::PaymentMethodSerializer.class_eval do
    def self.serializer_for(model, params)
      case model
      when Spree::PaymentMethod::Ipay
        Spree::Api::V2::Platform::IpaySourceSerializer
      else
        super
      end
    end
  end
end
