# frozen_string_literal: true

Spree::Core::Engine.routes.draw do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      post '/ipay/:payment_id/callback', to: 'ipay#callback', as: :spree_ipay_callback
      get '/ipay/callback', to: 'ipay#callback', as: :spree_ipay_callback_get
      get '/ipay/:payment_id/return', to: 'ipay#return', as: :spree_ipay_return
      get '/ipay/:payment_id/status', to: 'ipay#status', as: :spree_ipay_status
    end
  end

  get '/ipay/checkout/:id', to: 'ipay#interactive_checkout', as: :ipay_interactive_checkout
end