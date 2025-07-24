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
      
      # Extract parameters from both query string and form data
      txn_id = params[:txnid] || params['txnid']
      status = params[:status] || params['status']
      order_number = params[:order_id] || params['order_id'] || 
                    params[:id] || params['id'] || 
                    params[:ivm] || params['ivm'] || 
                    params[:oid] || params['oid']
                    
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
            # --- iPay C2B SHA1 HMAC Signature Verification ---
            required_keys = %w[live oid inv ttl tel eml vid curr p1 p2 p3 p4 cbk cst crl]
            param_values = required_keys.map { |k| params[k] || params[k.to_sym] }
            if param_values.all?
              datastring = param_values.join
              hash_key = payment.payment_method.preferred_hash_key if payment.payment_method.respond_to?(:preferred_hash_key)
              received_signature = params[:hsh] || params[:hash]
              generated_signature = OpenSSL::HMAC.hexdigest('sha1', hash_key, datastring)
              unless ActiveSupport::SecurityUtils.secure_compare(generated_signature, received_signature.to_s)
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
            # --- Amount Verification ---
            paid_amount = params['mc'].to_f
            required_amount = order.total.to_f
            if paid_amount < required_amount
              @heading = 'Insufficient Payment'
              @message = "Amount paid (#{paid_amount}) is less than required (#{required_amount})"
              render 'failure', status: :payment_required
              return
            end
            # iPay status code handling
            Rails.logger.info("[#{@request_id}] Processing iPay status: #{status}")
            status_map = {
              'aei7p7yrx4ae34' => { label: 'Success', heading: 'Order Placed Successfully!' },
              'fe2707etr5s4wq' => { label: 'Failed', heading: 'Payment Failed' },
              'bdi6p2yy76etrs' => { label: 'Pending', heading: 'Payment Pending' },
              'cr5i3pgy9867e1' => { label: 'Used', heading: 'Code Already Used' },
              'dtfi4p7yty45wq' => { label: 'Less', heading: 'Insufficient Payment' },
              'eq3i7p5yt7645e' => { label: 'More', heading: 'Overpayment' }
            }
            code = status.to_s
            meta = status_map[code] || { label: 'Unknown', heading: 'Payment Failed' }
            @heading = meta[:heading]
            @message = params[:message] || meta[:label]
            if code == 'aei7p7yrx4ae34'
              payment.update(response_code: txn_id) if txn_id.present?
              payment.complete! if payment.respond_to?(:can_complete?) ? payment.can_complete? : !payment.completed?
              order.next! until order.completed? rescue nil
              render 'success', status: :ok
            elsif code == 'bdi6p2yy76etrs'
              render 'pending', status: :ok
            else
              if payment.respond_to?(:can_failure?) && payment.can_failure?
                payment.failure!
              end
              render 'failure', status: :payment_required
            end
            return
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
