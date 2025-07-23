# frozen_string_literal: true

module Spree
  module Api
    module V1
      # Handles API endpoints for iPay payment processing.
      # Provides endpoints for callbacks from iPay and payment status checks.
      # Skips authentication for callback endpoints to allow external access.
      class IpayController < Spree::Api::V1::BaseController
        # Only load payment for :return, not for :callback (GET/POST)
        before_action :load_payment, only: [:return]
        skip_before_action :load_payment, only: [:callback]

        # SKIP ALL USER-RELATED AUTH FOR CALLBACK (SECURITY BY HASH ONLY)
        skip_before_action :authenticate_user, only: %i[callback return]
        # skip_before_action :authenticate_spree_user, only: [:callback, :return]
        skip_before_action :load_user, only: %i[callback return] # If present in base
        skip_before_action :set_locale, only: %i[callback return] # Avoids user-locale issues

        # iPay callback endpoint
        def callback
          # Log the raw request parameters and body for debugging
          Rails.logger.info("[iPay Callback] Raw request parameters: #{params.to_unsafe_h}")
          Rails.logger.info("[iPay Callback] Request method: #{request.method}")
          
          # For POST requests, log the raw body
          if request.post?
            begin
              raw_body = request.raw_post
              Rails.logger.info("[iPay Callback] Raw POST body: #{raw_body}")
              
              # Try to parse as JSON if content-type is application/json
              if request.content_type == 'application/json'
                json_params = JSON.parse(raw_body) rescue {}
                params.merge!(json_params)
                Rails.logger.info("[iPay Callback] Parsed JSON params: #{json_params}")
              end
            rescue => e
              Rails.logger.error("[iPay Callback] Error parsing request body: #{e.message}")
            end
          end
          
          # Extract order reference from various possible parameters
          order_reference = params[:id] || params[:oid] || params[:order_id] || params[:order_number]
          
          if order_reference.blank?
            error_msg = 'Order reference is required. Available params: ' + params.to_unsafe_h.inspect
            Rails.logger.error("[iPay Callback] #{error_msg}")
            render json: { 
              status: 'error', 
              message: 'Order reference is required',
              received_params: params.to_unsafe_h
            }, status: :bad_request
            return
          end

          # Find the order by number or ID
          order = Spree::Order.find_by(number: order_reference) || Spree::Order.find_by(id: order_reference)

          if order.nil?
            render json: { status: 'error', message: 'Order not found' }, status: :not_found
            return
          end

          # Find all payments for this order
          all_payments = order.payments.includes(:payment_method).to_a

          # Try to find the payment with more flexible matching
          @payment = all_payments.detect do |p|
            p.payment_method&.type&.include?('Ipay') ||
              p.payment_method&.name&.downcase&.include?('ipay')
          end

          # If still not found, try to find any pending/checkout payment
          @payment ||= all_payments.detect { |p| %w[pending checkout].include?(p.state) }

          if @payment.nil?
            render json: {
              status: 'error',
              message: 'No suitable payment found for this order',
              order_number: order.number,
              order_id: order.id
            }, status: :not_found
            return
          end

          # Update the response code with the transaction ID if we have one
          if params[:txncd].present? && @payment.response_code != params[:txncd]
            @payment.update(response_code: params[:txncd])
          end

          begin
            # Verify the callback authenticity
            if verify_callback_hash

              # Extract status from params and normalize it
              status = params[:status].to_s.downcase
              normalized_status = case status
                                  when 'aei7p7yrx4ae34', 'success', 'completed', 'paid' then 'success'
                                  when 'bdi6p2yy76etrs', 'pending', 'processing' then 'pending'
                                  when 'fe2707etr5s4wq', 'failed', 'cancelled', 'error' then 'failed'
                                  else status
                                  end

              # Update payment state based on status
              case normalized_status
              when 'success'
                order = @payment.order

                # Complete the payment if not already completed
                unless @payment.completed?
                  @payment.complete! unless @payment.completed?

                  # Advance order to complete state if needed
                  order.next! until order.completed?

                  # Update order state if needed
                  if (order.respond_to?(:can_complete?) && order.can_complete? && !order.completed?) ||
                     (order.respond_to?(:completable?) && order.completable? && !order.completed?)
                    order.complete!
                  end
                end

                # Generate the order completion URL with ngrok host
                ngrok_host = 'a35d-129-222-187-17.ngrok-free.app'

                # Safely get guest token using the correct method
                guest_token = order.respond_to?(:token) ? order.token : nil
                token_param = guest_token.present? ? "?token=#{guest_token}" : ""

                order_url = "https://#{ngrok_host}/orders/#{order.number}#{token_param}"

                # Handle both HTML and JSON responses
                respond_to do |format|
                  format.json do
                    render json: {
                      status: 'success',
                      message: 'Payment processed successfully',
                      order_state: order.state,
                      order_number: order.number,
                      payment_id: @payment.id,
                      transaction_id: @payment.response_code,
                      redirect_url: order_url,
                      order_completed: order.completed?,
                      payment_completed: @payment.completed?
                    }, status: :ok
                  end
                  format.html do
                    redirect_to order_url, notice: 'Payment processed successfully'
                  end
                end
              when 'pending'
                @payment.started_processing! if @payment.checkout?
                render json: {
                  status: 'pending',
                  message: 'Payment is being processed',
                  order_number: @payment.order.number,
                  payment_id: @payment.id
                }, status: :ok

              when 'failed'
                @payment.failure! unless @payment.failed?
                render json: {
                  status: 'failed',
                  message: 'Payment processing failed',
                  order_number: @payment.order.number,
                  payment_id: @payment.id
                }, status: :unprocessable_entity

              else

                render json: {
                  status: 'error',
                  message: "Unknown payment status: #{status}",
                  order_number: @payment.order.number,
                  payment_id: @payment.id
                }, status: :unprocessable_entity
              end
            else

              render json: {
                status: 'failed',
                message: 'Invalid callback signature',
                payment_id: @payment.id,
                order_number: @payment.order.number
              }, status: :unauthorized
            end
          rescue StandardError
            render json: { status: 'error', message: 'Internal server error' }, status: :internal_server_error
          end
        end

        # iPay return endpoint (customer redirect)
        def return
          order = @payment.order

          # If payment is already completed, redirect to order confirmation
          if @payment.completed?

            redirect_to spree.order_path(order, order_token: order.guest_token),
                        notice: Spree.t(:order_processed_successfully)
            return
          end

          # If payment is processing, check with iPay for status
          if @payment.pending? || @payment.processing?

            # Here you might want to implement a status check with iPay
            # For now, we'll just redirect to payment info page
            redirect_to spree.checkout_state_path(:payment),
                        notice: 'We are still processing your payment. Please check back soon.'
            return
          end

          # If payment failed
          if @payment.failed? || @payment.void?

            redirect_to spree.checkout_state_path(:payment),
                        alert: 'Payment was not completed. Please try again or use a different payment method.'
            return
          end

          # Default fallback
          redirect_to spree.checkout_state_path(order.state),
                      notice: 'Please complete your order.'
        rescue StandardError
          redirect_to spree.root_path,
                      alert: 'An error occurred while processing your order. Please contact support if the problem persists.'
        end

        # Check payment status endpoint
        def status
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
        rescue StandardError
          render json: { status: 'error', message: 'Internal server error' }, status: :internal_server_error
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
          # Log all received parameters for debugging
          Rails.logger.info("[iPay Callback] Received parameters: #{params.to_unsafe_h}")
          
          received_hash = params[:hash] || params[:hsh] # Check both hash and hsh parameters
          payment_method = @payment.payment_method

          # Log the payment method being used
          Rails.logger.info("[iPay Callback] Payment method: #{payment_method&.class&.name}")
          Rails.logger.info("[iPay Callback] Received hash: #{received_hash}")

          # Skip verification if no hash is provided (for testing)
          if received_hash.blank?
            Rails.logger.warn("[iPay Callback] No hash provided, skipping verification")
            return true 
          end

          # Only require hash verification for real iPay payment methods
          if payment_method.class.name.demodulize.downcase.include?("ipay") && payment_method.respond_to?(:generate_status_hash)
            if @payment.response_code.blank?
              Rails.logger.error("[iPay Callback] No response code available for payment")
              return false
            end

            begin
              # Log the transaction ID being used for verification
              Rails.logger.info("[iPay Callback] Verifying hash for transaction: #{@payment.response_code}")
              
              # Generate the expected hash
              expected_hash = payment_method.send(:generate_status_hash, @payment.response_code)
              
              # Log both hashes for comparison
              Rails.logger.info("[iPay Callback] Expected hash: #{expected_hash}")
              Rails.logger.info("[iPay Callback] Received hash: #{received_hash}")
              
              # Compare hashes in a timing-safe way
              ActiveSupport::SecurityUtils.secure_compare(
                ::Digest::SHA1.hexdigest(expected_hash.to_s),
                ::Digest::SHA1.hexdigest(received_hash.to_s)
              )
            rescue StandardError => e
              Rails.logger.error("[iPay Callback] Error verifying hash: #{e.message}\n#{e.backtrace.join("\n")}")
              false
            end
          else
            # Skip verification for non-iPay payment methods
            Rails.logger.warn("[iPay Callback] Skipping verification for non-iPay payment method")
            true
          end
        end
      end
    end
  end
end
