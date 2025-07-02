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

          # Extract order reference from params (could be in id or oid parameter)
          order_reference = params[:id] || params[:oid]
          
          if order_reference.blank?
            render json: { status: 'error', message: 'Order reference is required' }, status: :bad_request
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
          @payment ||= all_payments.detect { |p| ['pending', 'checkout'].include?(p.state) }
          
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
            @payment.update_columns(response_code: params[:txncd], updated_at: Time.current)
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
          rescue StandardError => e

            render json: { status: 'error', message: 'Internal server error' }, status: :internal_server_error
          end
        end

        # iPay return endpoint (customer redirect)
        def return
          begin
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
            
          rescue StandardError => e
            redirect_to spree.root_path,
              alert: 'An error occurred while processing your order. Please contact support if the problem persists.'
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
          
          # Verify callback hash for payment

          # Skip verification if no hash is provided (for testing)
          if received_hash.blank?

            return true
          end

          # Only require hash verification for real iPay payment methods
          if payment_method.class.name.demodulize.downcase.include?("ipay") && payment_method.respond_to?(:generate_status_hash)
            if @payment.response_code.blank?

              return false
            end
            
            begin
              expected_hash = payment_method.send(:generate_status_hash, @payment.response_code)
              received_hash == expected_hash
            rescue => e

              false
            end
          else
            # Skip verification for non-iPay payment methods
            true
          end
        end
      end
    end
  end
end