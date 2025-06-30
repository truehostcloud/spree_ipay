module Spree
  class IpayController < Spree::StoreController
    protect_from_forgery except: :callback
    
    # iPay callback endpoint - handles both test and live environments
    # POST /ipay/callback
    def callback
      Rails.logger.info "iPay CALLBACK RECEIVED"
      Rails.logger.info "Raw callback params: #{params.to_unsafe_h.inspect}"
      
      begin
        # Extract iPay callback parameters based on current documentation
        transaction_data = extract_callback_params
        
        # Verify the callback authenticity
        unless verify_ipay_callback(transaction_data)
          Rails.logger.error "iPay callback verification failed"
          render json: { status: 0, message: "Invalid callback signature" }, status: :unauthorized
          return
        end
        
        # Find the order using the order ID from iPay
        order = find_order_by_reference(transaction_data[:order_id])
        return unless order
        
        # Find the associated payment
        payment = find_payment_for_order(order)
        return unless payment
        
        # Update payment with iPay transaction details
        update_payment_details(payment, transaction_data)
        
        # Process payment based on status
        process_payment_status(payment, order, transaction_data)
        
      rescue => e
        Rails.logger.error "iPay Callback Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { status: 0, message: "Internal server error" }, status: :internal_server_error
      end
    end
    
    # Interactive checkout method for redirecting to iPay
    def interactive_checkout
      Rails.logger.info "iPay checkout controller started"
      
      begin
        @order = Spree::Order.find_by!(number: params[:id])
        Rails.logger.info "iPay checkout request for Order #{@order.number}"
        
        # Get stored session data
        phone = session[:ipay_phone_number]
        redirect_url = session[:ipay_redirect_url]
        
        Rails.logger.info "Phone: #{phone}, Redirect URL: #{redirect_url}"
        
        if redirect_url.present?
          # Clear session data
          session.delete(:ipay_phone_number)
          session.delete(:ipay_redirect_url)
          
          Rails.logger.info "Redirecting to iPay: #{redirect_url}"
          redirect_to redirect_url
        else
          Rails.logger.warn "No redirect URL found for Order #{@order.number}"
          redirect_to spree.checkout_state_path(:payment), 
                     alert: 'Payment session expired. Please try again.'
        end
        
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error "Order not found: #{params[:id]}"
        redirect_to spree.root_path, alert: 'Order not found'
      rescue => e
        Rails.logger.error "Checkout Error: #{e.message}"
        redirect_to spree.checkout_state_path(:payment), 
                   alert: 'Error processing payment. Please try again.'
      end
    end
    
    private
    
    # Extract callback parameters based on iPay documentation
    def extract_callback_params
      {
        # Core transaction details
        transaction_id: params[:txncd],
        order_id: params[:id] || params[:oid],
        invoice: params[:ivm],
        status: params[:status]&.downcase,
        amount: params[:mc],
        
        # Customer details
        customer_phone: params[:msisdn_idnum],
        customer_name: params[:msisdn_id],
        customer_account: params[:msisdn_custnum],
        
        # iPay system variables for verification
        qwh: params[:qwh],
        afd: params[:afd],
        poi: params[:poi],
        uyt: params[:uyt],
        ifd: params[:ifd],
        agt: params[:agt],
        
        # Custom parameters
        p1: params[:p1],
        p2: params[:p2],
        p3: params[:p3],
        p4: params[:p4],
        
        # Additional fields
        channel: params[:channel],
        card_mask: params[:card_mask],
        vat: params[:vat],
        commission: params[:commission]
      }
    end
    
    # Verify iPay callback using IPN (Instant Payment Notification)
    def verify_ipay_callback(transaction_data)
      return true if Rails.env.test? # Skip verification in test environment
      
      vendor_id = ENV['IPAY_VENDOR_ID'] || 'demo'
      
      # Build IPN verification URL as per iPay documentation
      ipn_url = build_ipn_url(vendor_id, transaction_data)
      
      begin
        # Make IPN verification request
        response = make_ipn_request(ipn_url)
        
        # Check if response matches expected status
        verified_status = response.strip.downcase
        actual_status = normalize_status(transaction_data[:status])
        
        Rails.logger.info "IPN Response: #{verified_status}, Actual Status: #{actual_status}"
        
        return verified_status == actual_status
        
      rescue => e
        Rails.logger.error "IPN Verification failed: #{e.message}"
        return false
      end
    end
    
    # Build IPN verification URL
    def build_ipn_url(vendor_id, transaction_data)
      base_url = "https://www.ipayafrica.com/ipn/"
      params = {
        vendor: vendor_id,
        id: transaction_data[:order_id],
        ivm: transaction_data[:invoice],
        qwh: transaction_data[:qwh],
        afd: transaction_data[:afd],
        poi: transaction_data[:poi],
        uyt: transaction_data[:uyt],
        ifd: transaction_data[:ifd]
      }
      
      "#{base_url}?#{params.to_query}"
    end
    
    # Make IPN verification request
    def make_ipn_request(url)
      require 'net/http'
      uri = URI(url)
      
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = 'Spree iPay Integration'
        
        response = http.request(request)
        response.body
      end
    end
    
    # Normalize status codes for comparison
    def normalize_status(status)
      case status&.downcase
      when 'aei7p7yrx4ae34', 'success', 'completed', 'paid'
        'aei7p7yrx4ae34'
      when 'bdi6p2yy76etrs', 'pending', 'processing'
        'bdi6p2yy76etrs'
      when 'fe2707etr5s4wq', 'failed', 'cancelled', 'error'
        'fe2707etr5s4wq'
      else
        status&.downcase
      end
    end
    
    # Find order by reference
    def find_order_by_reference(order_reference)
      order = Spree::Order.find_by(number: order_reference)
      
      if order.nil?
        Rails.logger.error "Order not found: #{order_reference}"
        render json: { status: 0, message: "Order not found" }, status: :not_found
        return nil
      end
      
      order
    end
    
    # Find payment for order
    def find_payment_for_order(order)
      payment = order.payments.where(payment_method: Spree::PaymentMethod::Ipay).last
      
      if payment.nil?
        Rails.logger.error "No iPay payment found for order: #{order.number}"
        render json: { status: 0, message: "Payment not found" }, status: :not_found
        return nil
      end
      
      payment
    end
    
    # Update payment with transaction details
    def update_payment_details(payment, transaction_data)
      if payment.response_code.blank? && transaction_data[:transaction_id].present?
        payment.update_columns(
          response_code: transaction_data[:transaction_id],
          avs_response: transaction_data[:channel],
          cvv_response_code: transaction_data[:customer_phone],
          updated_at: Time.current
        )
      end
    end
    
    # Process payment based on status
    def process_payment_status(payment, order, transaction_data)
      status = normalize_status(transaction_data[:status])
      
      Rails.logger.info "Processing payment #{payment.number} with status: #{status}"
      
      case status
      when 'aei7p7yrx4ae34' # Success
        handle_successful_payment(payment, order, transaction_data)
        
      when 'bdi6p2yy76etrs' # Pending
        handle_pending_payment(payment, order)
        
      when 'fe2707etr5s4wq' # Failed
        handle_failed_payment(payment, order)
        
      when 'cr5i3pgy9867e1' # Used/Duplicate
        handle_duplicate_payment(payment, order)
        
      when 'dtfi4p7yty45wq' # Less amount
        handle_insufficient_payment(payment, order, transaction_data)
        
      when 'eq3i7p5yt7645e' # More amount
        handle_overpayment(payment, order, transaction_data)
        
      else
        handle_unknown_status(payment, order, status)
      end
    end
    
    # Handle successful payment
    def handle_successful_payment(payment, order, transaction_data)
      unless payment.completed?
        begin
          payment.complete!
          order.next! until order.completed?
          
          Rails.logger.info "Payment completed successfully for order #{order.number}"
          
          # Send success response to iPay
          render json: { 
            status: 1, 
            id: transaction_data[:transaction_id], 
            message: "Success" 
          }
          
        rescue => e
          Rails.logger.error "Error completing payment: #{e.message}"
          render json: { 
            status: 0, 
            id: transaction_data[:transaction_id], 
            message: "Failed to complete payment" 
          }
        end
      else
        Rails.logger.info "Payment already completed for order #{order.number}"
        render json: { 
          status: 2, 
          id: transaction_data[:transaction_id], 
          message: "Duplicate" 
        }
      end
    end
    
    # Handle pending payment
    def handle_pending_payment(payment, order)
      payment.started_processing! if payment.checkout?
      Rails.logger.info "Payment marked as pending for order #{order.number}"
      
      render json: { 
        status: 1, 
        id: payment.number, 
        message: "Payment pending" 
      }
    end
    
    # Handle failed payment
    def handle_failed_payment(payment, order)
      unless payment.failed?
        payment.failure!
        Rails.logger.warn "Payment marked as failed for order #{order.number}"
      end
      
      render json: { 
        status: 0, 
        id: payment.number, 
        message: "Payment failed" 
      }
    end
    
    # Handle duplicate payment
    def handle_duplicate_payment(payment, order)
      Rails.logger.warn "Duplicate payment attempt for order #{order.number}"
      
      render json: { 
        status: 2, 
        id: payment.number, 
        message: "Duplicate transaction" 
      }
    end
    
    # Handle insufficient payment
    def handle_insufficient_payment(payment, order, transaction_data)
      Rails.logger.warn "Insufficient payment for order #{order.number}. " \
                       "Expected: #{order.total}, Received: #{transaction_data[:amount]}"
      
      render json: { 
        status: 0, 
        id: payment.number, 
        message: "Insufficient payment amount" 
      }
    end
    
    # Handle overpayment
    def handle_overpayment(payment, order, transaction_data)
      Rails.logger.info "Overpayment for order #{order.number}. " \
                       "Expected: #{order.total}, Received: #{transaction_data[:amount]}"
      
      # You can decide whether to accept overpayments or not
      # For now, we'll accept them as successful
      handle_successful_payment(payment, order, transaction_data)
    end
    
    # Handle unknown status
    def handle_unknown_status(payment, order, status)
      Rails.logger.warn "Unknown payment status '#{status}' for order #{order.number}"
      
      render json: { 
        status: 0, 
        id: payment.number, 
        message: "Unknown payment status" 
      }
    end
  end
end