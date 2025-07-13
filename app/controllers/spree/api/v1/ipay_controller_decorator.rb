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
            
            # Authorization using Spree's built-in authorization
            authorize! :read, order
            
            payment = order.payments.valid.where(payment_method_id: @payment_method.id).last
            
            if payment
              render json: {
                status: payment.state,
                payment_id: payment.number,
                order_number: order.number
              }
            else
              render json: { status: 'error', message: 'No payment found' }, status: :not_found
            end
          rescue CanCan::AccessDenied
            render json: { status: 'error', message: 'Access denied' }, status: :forbidden
          rescue ActiveRecord::RecordNotFound
            render json: { status: 'error', message: 'Order not found' }, status: :not_found
          rescue => e
            Rails.logger.error("iPay API Error: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
            render json: { status: 'error', message: 'An error occurred' }, status: :internal_server_error
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
