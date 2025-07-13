# frozen_string_literal: true

module Spree
  module Api
    module V1
      module IpayControllerDecorator
        def self.prepended(base)
          base.respond_to :json
          base.skip_before_action :authenticate_user, only: [:callback, :return, :status]
          base.before_action :set_headers
        end

        # GET /api/v1/ipay/status
        def status
          @payment = Spree::Payment.find_by!(number: params[:order_id])
          
          render json: {
            status: 'success',
            payment: {
              id: @payment.id,
              number: @payment.number,
              state: @payment.state,
              amount: @payment.amount.to_f,
              created_at: @payment.created_at,
              updated_at: @payment.updated_at
            },
            order: {
              id: @payment.order.id,
              number: @payment.order.number,
              state: @payment.order.state,
              total: @payment.order.total.to_f,
              payment_state: @payment.order.payment_state,
              shipment_state: @payment.order.shipment_state
            }
          }
        rescue ActiveRecord::RecordNotFound
          render json: { status: 'error', message: 'Payment not found' }, status: :not_found
        end

        private

        def set_headers
          response.headers['Cache-Control'] = 'no-cache, no-store, max-age=0, must-revalidate'
          response.headers['Pragma'] = 'no-cache'
          response.headers['Expires'] = 'Fri, 01 Jan 1990 00:00:00 GMT'
        end
      end
    end
  end
end

Spree::Api::V1::IpayController.prepend(Spree::Api::V1::IpayControllerDecorator) if defined?(Spree::Api::V1::IpayController)
