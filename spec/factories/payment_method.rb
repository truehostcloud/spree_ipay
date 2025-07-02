# frozen_string_literal: true

FactoryBot.define do
  factory :payment_method, class: 'Spree::PaymentMethod' do
    name { 'Manual' }
    type { 'Spree::PaymentMethod' }
    stores { [Spree::Store.first || association(:store)] }
    preferred_vendor_id { 'demo' }
    preferred_hash_key { 'demohash' }
    preferred_test_mode { true }
    trait :ipay do
      type { 'Spree::PaymentMethod::Ipay' }
      name { 'iPay' }
    end
  end
end
