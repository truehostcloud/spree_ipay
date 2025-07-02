# frozen_string_literal: true

FactoryBot.define do
  factory :payment_method_ipay, class: 'Spree::PaymentMethod::Ipay' do
    name { 'iPay' }
    type { 'Spree::PaymentMethod::Ipay' }
    stores { [Spree::Store.first || association(:store)] }
    preferred_vendor_id { 'demo' }
    preferred_hash_key { 'demohash' }
    preferred_test_mode { true }
  end
end
