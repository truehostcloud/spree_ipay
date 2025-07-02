# frozen_string_literal: true

FactoryBot.define do
  factory :payment, class: 'Spree::Payment' do
    amount { 100.0 }
    order { Spree::Order.first || association(:order) }
    payment_method { Spree::PaymentMethod.first || association(:payment_method) }
    state { 'checkout' }
  end
end
