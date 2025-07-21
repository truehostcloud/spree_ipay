# frozen_string_literal: true

Spree::Core::Engine.routes.draw do
  # iPay payment confirmation callback
  get '/ipay/confirm', to: 'gateway_callbacks#confirm'
  get '/ipay/checkout/:id', to: 'ipay#interactive_checkout', as: :ipay_interactive_checkout
  
  # API endpoints
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :ipay, only: [] do
        collection do
          get :status
          post :callback
        end
      end
    end
  end
  
  # Fallback for API requests without format
  get '/api/v1/ipay/status', to: 'api/v1/ipay#status', defaults: { format: 'json' }
  post '/api/v1/ipay/callback', to: 'api/v1/ipay#callback', defaults: { format: 'json' }
end
