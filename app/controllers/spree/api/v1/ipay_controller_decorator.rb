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
          order = Spree::Order.find_by!(number: params[:order_id])
          
          # Authorization check - only allow order owner or admin
          if !current_api_user || (order.user_id != current_api_user.id && !current_api_user.has_spree_role?('admin'))
            render json: { error: 'Unauthorized' }, status: :unauthorized
            return
          end
          
          payment = order.payments.valid.where(payment_method_id: @payment_method.id).last
          
          if payment
            render json: {
              status: payment.state,
              payment_id: payment.number,
              order_number: order.number,
              amount: payment.amount.to_f,
              currency: payment.currency,
              shipment_state: payment.order.shipment_state
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
