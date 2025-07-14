# frozen_string_literal: true

module Spree
  module Api
    module V1
      module IpayControllerDecorator
        def self.prepended(base)
          base.respond_to :json
          # Only skip authentication for callbacks and return URLs which need to be publicly accessible
          base.skip_before_action :authenticate_user, only: [:callback, :return]
          base.before_action :set_headers
          base.before_action :set_payment_method, only: [:status]
          base.before_action :authenticate_for_status, only: [:status]
        end

        # GET /api/v1/ipay/status
        # @order is set in authenticate_for_status
        def status
          begin
            # Find the most recent valid payment for this order and payment method
            payment = @order.payments.valid
                          .where(payment_method_id: @payment_method.id)
                          .order(created_at: :desc)
                          .first
            
            if payment
              render json: {
                status: payment.state,
                payment_id: payment.number,
                order_number: @order.number
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
          # Use the actual class constant instead of string to prevent type confusion
          ipay_class = Spree::PaymentMethod::Ipay
          
          # Find the first active iPay payment method
          @payment_method = Spree::PaymentMethod.available.detect do |pm|
            pm.is_a?(ipay_class) && pm.active?
          end
          
          return if @payment_method
          
          render json: { status: 'error', message: 'iPay payment method not found or not active' }, status: :unprocessable_entity
        end

        def authenticate_for_status
          # Ensure the order exists
          @order = Spree::Order.find_by(number: params[:order_id])
          unless @order
            render json: { status: 'error', message: 'Order not found' }, status: :not_found
            return
          end
          
          # For authenticated users, verify they have permission
          if spree_current_user
            authorize! :read, @order
            return
          end
          
          # For guest users, require both email and token
          if guest_authentication_required?
            render json: { status: 'error', message: 'Authentication required' }, status: :unauthorized
            return
          end
          
        rescue CanCan::AccessDenied
          render json: { status: 'error', message: 'Access denied' }, status: :forbidden
        end
        
        private
        
        # Constant-time comparison that doesn't short-circuit
        # @param actual_value [String] The actual value to check against
        # @param input_value [String] The user-provided input to validate
        # @return [Boolean] true if values match (case-insensitive, trimmed), false otherwise
        def constant_time_compare(actual_value, input_value)
          return false if actual_value.blank? || input_value.blank?
  
          # Convert to strings but avoid normalization that could introduce timing variations
          actual = actual_value.to_s
          input = input_value.to_s
  
          # Use a constant-time comparison that always compares all bytes
          ActiveSupport::SecurityUtils.secure_compare(actual, input)
        rescue ArgumentError
          # If byte lengths don't match, secure_compare raises an ArgumentError
          false
        end
        
        def guest_authentication_required?
          # Always perform both checks to prevent timing attacks
          token_ok = constant_time_compare(@order.guest_token, params[:token])
          email_ok = constant_time_compare(@order.email, params[:email])
          
          # Return true if authentication is required (either check failed)
          !(token_ok && email_ok)
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
