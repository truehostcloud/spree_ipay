# frozen_string_literal: true

FactoryBot.define do
  factory :payment_method_ipay, class: 'Spree::PaymentMethod::Ipay' do
    name 'iPay'
    description 'iPay Payment Method'
    active true
    display_on :both
    auto_capture true

    preferences do
      {
        vendor_id: 'demo',
        hash_key: 'demoCHANGED',
        test_mode: true
      }
    end
  end
end
