# frozen_string_literal: true

Spree::Core::Engine.routes.draw do
  # iPay payment confirmation callback
  get '/ipay/confirm', to: 'gateway_callbacks#confirm'


  get '/ipay/checkout/:id', to: 'ipay#interactive_checkout', as: :ipay_interactive_checkout
end