# frozen_string_literal: true

FactoryBot.define do
  factory :ipay_source, class: 'Spree::IpaySource' do
    phone { '0700123456' }
    payment_method { Spree::PaymentMethod::Ipay.first || association(:payment_method_ipay) }
  end
end
