module Spree
  # Handles callbacks from the iPay payment gateway.
  # Processes payment confirmations and updates order statuses based on iPay responses.
  # This controller skips CSRF protection for the confirm action to allow external callbacks.
  class GatewayCallbacksController < ApplicationController
    layout false # Don't use the application layout
    skip_before_action :verify_authenticity_token, only: [:confirm]

    def confirm
      # Log all incoming parameters for debugging
      request_id = SecureRandom.hex(4)
      Rails.logger.info("\n===== iPay CALLBACK RECEIVED [Request ID: #{request_id}] =====")
      Rails.logger.info("[#{request_id}] Request method: #{request.method}")
      Rails.logger.info("[#{request_id}] Request URL: #{request.url}")
      Rails.logger.info("[#{request_id}] Request format: #{request.format}")
      
      # Log all headers
      Rails.logger.info("[#{request_id}] === Headers ===")
      request.headers.each do |key, value|
        Rails.logger.info("[#{request_id}] #{key}: #{value}") if key.to_s.downcase.include?('http') || key.to_s.downcase.include?('content')
      end
      
      # Log all parameters
      Rails.logger.info("[#{request_id}] === Parameters ===")
      params.each do |key, value|
        Rails.logger.info("[#{request_id}] #{key}: #{value}")
      end
      
      # Log raw body if present
      raw_body = request.body.read
      request.body.rewind # Reset the body for potential future reads
      
      if raw_body.present?
        Rails.logger.info("[#{request_id}] === Raw Body ===")
        Rails.logger.info("[#{request_id}] #{raw_body}")
        
        # Try to parse JSON if content-type is JSON
        if request.content_type&.include?('application/json')
          begin
            json_body = JSON.parse(raw_body)
            Rails.logger.info("[#{request_id}] === Parsed JSON ===")
            json_body.each { |k,v| Rails.logger.info("[#{request_id}] #{k}: #{v}") }
          rescue JSON::ParserError => e
            Rails.logger.error("[#{request_id}] Failed to parse JSON: #{e.message}")
          end
        end
      end
      
      # Log form data if present
      if request.form_data?
        Rails.logger.info("[#{request_id}] === Form Data ===")
        request.request_parameters.each { |k,v| Rails.logger.info("[#{request_id}] #{k}: #{v}") }
      end
      
      # Log query string parameters
      if request.query_string.present?
        Rails.logger.info("[#{request_id}] === Query String ===")
        Rails.logger.info("[#{request_id}] #{request.query_string}")
      end
      
      # Log IP and other request details
      Rails.logger.info("[#{request_id}] === Request Details ===")
      Rails.logger.info("[#{request_id}] Remote IP: #{request.remote_ip}")
      Rails.logger.info("[#{request_id}] User Agent: #{request.user_agent}")
      Rails.logger.info("[#{request_id}] SSL: #{request.ssl?}")
      Rails.logger.info("[#{request_id}] XHR: #{request.xhr?}")
      
      # Store request ID in instance variable for use in error responses
      @request_id = request_id
      
      # Extract parameters from both query string (GET) and form data (POST)
      # For GET requests, parameters come in the query string
      # For POST requests, they come in the request body
      params_source = request.get? ? request.query_parameters : request.request_parameters
      
      # Log the source of the parameters
      Rails.logger.info("[#{@request_id}] Parameters source: #{request.get? ? 'GET (query string)' : 'POST (form data)'}")
      
      # Extract parameters with case-insensitive matching
      txn_id = params[:txnid] || params['txnid'] || params_source[:txnid] || params_source['txnid']
      status = params[:status] || params['status'] || params_source[:status] || params_source['status']
      order_number = params[:order_id] || params['order_id'] || params_source[:order_id] || params_source['order_id'] ||
                    params[:id] || params['id'] || params_source[:id] || params_source['id'] ||
                    params[:ivm] || params['ivm'] || params_source[:ivm] || params_source['ivm'] ||
                    params[:oid] || params['oid'] || params_source[:oid] || params_source['oid']
      
      # If no parameters are present in the URL, try to get the order from the session
      if order_number.blank? && session[:order_id].present?
        Rails.logger.info("[#{@request_id}] No order number in parameters, checking session for order_id: #{session[:order_id]}")
        order = Spree::Order.find_by(id: session[:order_id])
        order_number = order.number if order
      end
                    
      Rails.logger.info("Extracted - Txn ID: #{txn_id}, Status: #{status}, Order: #{order_number}")

      if order_number.present?
        Rails.logger.info("[#{@request_id}] Looking up order: #{order_number}")
        order = Spree::Order.find_by(number: order_number)
        
        if order
          Rails.logger.info("[#{@request_id}] Found order #{order.number}, state: #{order.state}")
          payment = order.payments.last
          
          if payment
            Rails.logger.info("[#{@request_id}] Found payment #{payment.number}, state: #{payment.state}, amount: #{payment.amount}")
            Rails.logger.info("[#{@request_id}] Payment method: #{payment.payment_method&.type}")
            
            # If payment is already completed, don't process it again
            if payment.completed?
              Rails.logger.info("[#{@request_id}] Payment is already completed. Redirecting to order page.")
              redirect_to spree.order_path(order, token: order.guest_token) and return
            end
            
            # --- iPay C2B SHA1 HMAC Signature Verification ---
            required_keys = %w[live oid inv ttl tel eml vid curr p1 p2 p3 p4 cbk cst crl]
            param_values = required_keys.map { |k| params[k] || params[k.to_sym] }
            if param_values.all?
              datastring = param_values.join
              hash_key = payment.payment_method.preferred_hash_key if payment.payment_method.respond_to?(:preferred_hash_key)
              received_signature = params[:hsh] || params[:hash]
              generated_signature = OpenSSL::HMAC.hexdigest('sha1', hash_key, datastring)
              hmac_verified = ActiveSupport::SecurityUtils.secure_compare(generated_signature, received_signature.to_s)
              unless hmac_verified
                error_msg = "[#{@request_id}] Invalid signature. Expected: #{generated_signature}, Received: #{received_signature}"
                Rails.logger.error(error_msg)
                @heading = 'Invalid Signature'
                @message = 'The payment signature could not be verified. Please contact support.'
                render 'failure', status: :unauthorized
                return
              else
                Rails.logger.info("[#{@request_id}] Signature verification successful")
              end
            end
            
            # Process the payment status
            case status&.downcase
            when 'success', 'aei7p7yrx4afh8d97hd97', 'aei7p7yrx4ae34'
              begin
                # Only process if payment isn't already completed
                unless payment.completed?
                  # Update payment with transaction ID
                  payment.update(response_code: txn_id) if txn_id.present?
                  
                  # Capture the payment amount
                  payment.capture! if payment.can_capture?
                  
                  # Complete the payment
                  payment.complete! if payment.can_complete?
                  
                  # Update order state
                  order.next! if order.payment_required? && !order.completed?
                  order.update_with_updater!
                  
                  Rails.logger.info("[#{@request_id}] Payment #{payment.number} completed successfully")
                end
                
                # Redirect to order confirmation page
                redirect_to spree.order_path(order, token: order.guest_token) and return
                
              rescue StandardError => e
                Rails.logger.error("[#{@request_id}] Error processing payment: #{e.message}")
                payment.failure! if payment.can_fail?
                redirect_to spree.checkout_state_path(:payment, error: 'Error processing payment') and return
              end
              
            when 'pending', 'bdi6p2yy76etrs'
              unless payment.pending?
                payment.pend! if payment.can_pend?
                order.update_with_updater!
              end
              
              @heading = 'Payment Pending'
              @message = 'Your payment is being processed. Please check back later for updates.'
              render 'pending', status: :ok
              
            when 'failed', 'bdi6p2yy76atrsf91sww'
              payment.failure! if payment.can_fail?
              order.update_with_updater!
              
              @heading = 'Payment Failed'
              @message = 'The payment was declined. Please try again or use a different payment method.'
              render 'failure', status: :payment_required
              
            else
              # Unknown status code
              payment.failure! if payment.can_fail?
              order.update_with_updater!
              
              @heading = 'Payment Error'
              @message = 'There was an error processing your payment. Please contact support.'
              render 'failure', status: :payment_required
            end
          else
            @heading = 'Payment Not Found'
            @message = 'No payment record found for this order.'
            render 'failure', status: :not_found
            return
          end
        else
          @heading = 'Order Not Found'
          @message = 'No order record could be found for this payment.'
          render 'failure', status: :not_found
          return
        end
      else
        @heading = 'Order Not Provided'
        @message = 'No order information was returned from iPay. This may be a browser redirect and not a server callback.'
        render 'failure', status: :bad_request
        return
      end
    rescue StandardError => e
      @heading = 'Error Processing Payment'
      @message = "An error occurred: #{e.message}"
      render 'failure', status: :internal_server_error
    end
  end
end
