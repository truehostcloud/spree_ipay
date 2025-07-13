# frozen_string_literal: true

module Spree
  module Api
    module V1
      module IpayControllerDecorator
        def self.prepended(base)
          base.respond_to :json
          base.skip_before_action :authenticate_user, only: [:callback, :return, :status]
          base.before_action :set_headers
          base.before_action :set_payment_method, only: [:status]
        end

        # GET /api/v1/ipay/status
        def status
          begin
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
            else
              render json: { status: 'error', message: 'No payment found for this order' }, status: :not_found
            end
          rescue ActiveRecord::RecordNotFound => e
            render json: { status: 'error', message: 'Order not found' }, status: :not_found
          rescue StandardError => e
            render json: { status: 'error', message: e.message }, status: :internal_server_error
          end
        end

        private

        def set_payment_method
          @payment_method = Spree::PaymentMethod.find_by(type: 'Spree::PaymentMethod::Ipay')
          return if @payment_method
          
          render json: { status: 'error', message: 'iPay payment method not configured' }, status: :unprocessable_entity
        end

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
