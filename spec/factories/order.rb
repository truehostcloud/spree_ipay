# frozen_string_literal: true

FactoryBot.define do
  factory :order, class: 'Spree::Order' do
    user
    bill_address
    ship_address
    email { user&.email || generate(:random_email) }
    store
    state { 'cart' }
    currency { 'KES' }

    transient do
      line_items_price { BigDecimal('100') }
      line_items_count { 1 }
    end

    after(:create) do |order, evaluator|
      create_list(:line_item, evaluator.line_items_count, order: order, price: evaluator.line_items_price)
      order.line_items.reload
      order.update_with_updater!
    end

    factory :order_ready_for_payment do
      state { 'payment' }
      payment_state { 'checkout' }
      email { 'test@example.com' }

      after(:create) do |order, evaluator|
        order.shipments.reload
        order.update_with_updater!
        order.next! # Advance to payment state
      end
    end
  end
end
