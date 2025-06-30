# frozen_string_literal: true

module Spree
  module Api
    module V1
      class IpayController < Spree::Api::V1::BaseController
        # Only load payment for :return, not for :callback (GET/POST)
        before_action :load_payment, only: [:return]
        skip_before_action :load_payment, only: [:callback]

        # SKIP ALL USER-RELATED AUTH FOR CALLBACK (SECURITY BY HASH ONLY)
        skip_before_action :authenticate_user, only: [:callback, :return]
        # skip_before_action :authenticate_spree_user, only: [:callback, :return]
        skip_before_action :load_user, only: [:callback, :return] # If present in base
        skip_before_action :set_locale, only: [:callback, :return] # Avoids user-locale issues


        # iPay callback endpoint
        def callback
          Rails.logger.info "OMKUU API V1 CALLBACK HIT"
          Rails.logger.info "OMKUU CALLBACK: Received params: #{params.to_unsafe_h.inspect}"

          # Always set @payment for both GET and POST
          txncd = params[:txncd] || params[:id] || params[:payment_id]
          @payment = Spree::Payment.find_by(response_code: txncd)
          if @payment.nil?
            Rails.logger.warn "OMKUU CALLBACK: Payment not found for txncd=#{txncd}"
            render json: { status: 'error', message: 'Payment not found' }, status: :not_found and return
          end

          begin
            # Verify the callback authenticity
            if verify_callback_hash
              Rails.logger.info "OMKUU CALLBACK: Callback hash verified for payment_id=#{@payment.id}"
              # Process the payment completion
              payment_method = @payment.payment_method
              if payment_method.respond_to?(:complete)
                response = payment_method.complete(@payment)
                Rails.logger.info "OMKUU CALLBACK: Called payment_method.complete, response: #{response.inspect}"
                if response.success?
                  render json: { status: 'success', message: response.message }, status: :ok
                else
                  render json: { status: 'failed', message: response.message }, status: :unprocessable_entity
                end
              else
                # For bogus/test gateway: handle status
                status_success = ['aei7p7yrx4ae34', 'success', 'paid', 'completed']
                status_failed = ['failed', 'cancelled', 'error']
                status = params[:status].to_s.downcase
                order = @payment.order

                if status_success.include?(status)
                  @payment.complete! if @payment.pending? || @payment.checkout?
                  order.next! until order.completed?
                  Rails.logger.info "OMKUU CALLBACK: Bogus/test gateway: payment and order marked complete (status: #{status})"
                  render json: { status: 'success', message: 'Payment processed successfully (bogus gateway)' }, status: :ok
                elsif status_failed.include?(status)
                  @payment.failure! if @payment.pending? || @payment.checkout?
                  Rails.logger.info "OMKUU CALLBACK: Bogus/test gateway: payment marked failed (status: #{status})"
                  render json: { status: 'failed', message: 'Payment failed or cancelled (bogus gateway)' }, status: :unprocessable_entity
                else
                  Rails.logger.warn "OMKUU CALLBACK: Bogus/test gateway: unknown status '#{status}'"
                  render json: { status: 'failed', message: 'Unknown payment status (bogus gateway)' }, status: :bad_request
                end
              end
            else
              Rails.logger.warn "OMKUU CALLBACK: Invalid callback signature for payment_id=#{@payment.id}"
              render json: { status: 'failed', message: 'Invalid callback signature' }, status: :unauthorized
            end
          rescue StandardError => e
            Rails.logger.error "OMKUU CALLBACK: Exception - #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
            render json: { status: 'error', message: 'Internal server error' }, status: :internal_server_error
          end
        end

        # iPay return endpoint (customer redirect)
        def return
          begin
            if @payment.completed?
              redirect_to spree.order_path(@payment.order), notice: 'Payment completed successfully!'
            else
              redirect_to spree.checkout_state_path(:payment), 
                         alert: 'Payment was not completed. Please try again.'
            end
          rescue StandardError => e
            Rails.logger.error "iPay Return Error: #{e.message}"
            redirect_to spree.root_path, alert: 'An error occurred processing your payment.'
          end
        end

        # Check payment status endpoint
        def status
          begin
            payment = Spree::Payment.find(params[:payment_id])
            payment_method = payment.payment_method
            
            if payment_method.is_a?(Spree::PaymentMethod::Ipay)
              status_response = payment_method.send(:check_payment_status, payment.response_code)
              render json: status_response
            else
              render json: { status: 'error', message: 'Invalid payment method' }, status: :bad_request
            end
          rescue ActiveRecord::RecordNotFound
            render json: { status: 'error', message: 'Payment not found' }, status: :not_found
          rescue StandardError => e
            Rails.logger.error "iPay Status Check Error: #{e.message}"
            render json: { status: 'error', message: 'Internal server error' }, status: :internal_server_error
          end
        end

        private

      # Dummy method to satisfy Spree API controller expectations
      def try_spree_current_user
        nil
      end

        def load_payment
          @payment = Spree::Payment.find(params[:payment_id])
        rescue ActiveRecord::RecordNotFound
          render json: { status: 'error', message: 'Payment not found' }, status: :not_found
        end

        def verify_callback_hash
          received_hash = params[:hash]
          payment_method = @payment.payment_method

          # Only require hash verification for real iPay payment methods
          if payment_method.class.name.demodulize.downcase.include?("ipay") && payment_method.respond_to?(:generate_status_hash)
            expected_hash = payment_method.send(:generate_status_hash, @payment.response_code)
            received_hash == expected_hash
          else
            # Allow for bogus/test gateways
            true
          end
        end
      end
    end
  end
end