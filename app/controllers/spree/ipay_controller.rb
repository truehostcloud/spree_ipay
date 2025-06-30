module Spree
  class IpayController < Spree::StoreController
    protect_from_forgery except: :callback
    
    # iPay callback endpoint - handles both test and live environments
    # POST /ipay/callback
    def callback
      # Callback processing started
      
      begin
        # Extract iPay callback parameters based on current documentation
        transaction_data = extract_callback_params
        
        # Transaction data extracted
        
        # Verify the callback authenticity
        unless verify_ipay_callback(transaction_data)
          render json: { 
            status: 0, 
            message: "Invalid callback signature",
            transaction_id: transaction_data[:transaction_id]
          }, status: :unauthorized
          return
        end
        
        # Find the order using the order ID from iPay
        order = find_order_by_reference(transaction_data[:order_id])
        unless order
          render json: { 
            status: 0, 
            message: "Order not found",
            order_reference: transaction_data[:order_id]
          }, status: :not_found
          return
        end
        
        # Find the associated payment
        payment = find_payment_for_order(order)
        unless payment
          render json: { 
            status: 0, 
            message: "Payment not found for this order",
            order_id: order.id,
            order_number: order.number,
            order_state: order.state
          }, status: :not_found
          return
        end
        # Update payment with iPay transaction details
        update_payment_details(payment, transaction_data)
        
        # Process payment based on status
        process_payment_status(payment, order, transaction_data)
        
      rescue => e
        error_response = { 
          status: 0, 
          message: "Payment processing failed",
          error: e.message,
          error_class: e.class.name
        }
        
        # Add debugging info in development
        if Rails.env.development?
          error_response[:backtrace] = e.backtrace
          error_response[:params] = params.to_unsafe_h
          error_response[:transaction_data] = transaction_data rescue {}
        end
        
        render json: error_response, status: :internal_server_error
      end
    end
    
    # Interactive checkout method for redirecting to iPay
    def interactive_checkout
      begin
        @order = Spree::Order.find_by!(number: params[:id])
        
        # Get stored session data
        phone = session[:ipay_phone_number]
        redirect_url = session[:ipay_redirect_url]
        
        if redirect_url.present?
          # Clear session data
          session.delete(:ipay_phone_number)
          session.delete(:ipay_redirect_url)
          
          redirect_to redirect_url, allow_other_host: true
        else
          redirect_to checkout_state_path(@order.state), alert: "Unable to process payment. Please try again."
        end
      rescue ActiveRecord::RecordNotFound => e
        redirect_to cart_path, alert: "Order not found."
      rescue => e
        redirect_to checkout_state_path(@order&.state || :cart), alert: "An error occurred while processing your payment. Please try again."
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
        
        return verified_status == actual_status
        
      rescue => e
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
    
    # Find order by reference (can be order ID or order number)
    def find_order_by_reference(order_reference)
      # First try to find by ID if reference is numeric
      if order_reference.to_s =~ /^\d+$/
        order = Spree::Order.find_by(id: order_reference)
      end
      
      # If not found by ID, try by order number
      order ||= Spree::Order.find_by(number: order_reference)
      
      if order.nil?
        return render json: { status: 0, message: "Order not found" }, status: :not_found
        return nil
      end
      

      order
    end
    
    def find_payment_for_order(order)
      all_payments = order.payments.to_a

      
      # Find only iPay payments
      ipay_payments = order.payments.where(payment_method: Spree::PaymentMethod::Ipay).order(created_at: :desc).to_a

      
      if ipay_payments.empty?
        # Try to find any pending or processing payments that might be iPay
        potential_payments = order.payments.where(state: ['checkout', 'processing', 'pending']).to_a
        potential_payments.each_with_index do |p, i|
        end
        
        render json: { 
          status: 0, 
          message: "No iPay payment found for this order",
          order_id: order.id,
          order_number: order.number,
          available_payments: all_payments.map { |p| {id: p.id, state: p.state, method: p.payment_method&.type} }
        }, status: :not_found
        return nil
      end
      
      # Get the most recent payment
      payment = ipay_payments.first

      
      payment
    rescue => e

      render json: { 
        status: 0, 
        message: "Error finding payment: #{e.message}",
        error: e.class.name,
        backtrace: []
      }, status: :internal_server_error
      nil
    end
    
    # Update payment with transaction details
    def update_payment_details(payment, transaction_data)
      updates = {}
      
      # Always update the response code if we have a transaction ID
      if transaction_data[:transaction_id].present? && payment.response_code != transaction_data[:transaction_id]
        updates[:response_code] = transaction_data[:transaction_id]
      end
      
      # Update additional payment details if available
      updates[:avs_response] = transaction_data[:channel] if transaction_data[:channel].present?
      updates[:cvv_response_code] = transaction_data[:customer_phone] if transaction_data[:customer_phone].present?
      updates[:updated_at] = Time.current
      
      # Only update if we have changes
      if updates.any? && payment.changed?
        payment.update_columns(updates)
      end
      
    rescue => e
      # Don't fail the entire callback if we can't update payment details
    end
    
    # Process payment based on status
    def process_payment_status(payment, order, transaction_data)
      status = normalize_status(transaction_data[:status])
      
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
          
          # Send success response to iPay
          render json: { 
            status: 1, 
            id: transaction_data[:transaction_id], 
            message: "Success" 
          }
          
        rescue => e

          render json: { 
            status: 0, 
            id: transaction_data[:transaction_id], 
            message: "Failed to complete payment" 
          }
        end
      else

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
      
      render json: { 
        status: 1, 
        id: payment.number, 
        message: "Payment pending" 
      }
    end
    
    # Handle failed payment
    def handle_failed_payment(payment, order)
      payment.failure! unless payment.failed?
      
      render json: { 
        status: 0, 
        id: payment.number, 
        message: "Payment failed" 
      }
    end
    
    # Handle duplicate payment
    def handle_duplicate_payment(payment, order)
      
      render json: { 
        status: 2, 
        id: payment.number, 
        message: "Duplicate transaction" 
      }
    end
    
    # Handle insufficient payment
    def handle_insufficient_payment(payment, order, transaction_data)
      render json: { 
        status: 0, 
        id: payment.number, 
        message: "Insufficient payment amount" 
      }
    end
    
    # Handle overpayment
    def handle_overpayment(payment, order, transaction_data)
      # You can decide whether to accept overpayments or not
      # For now, we'll accept them as successful
      handle_successful_payment(payment, order, transaction_data)
    end
    
    # Handle unknown status
    def handle_unknown_status(payment, order, status)

      
      render json: { 
        status: 0, 
        id: payment.number, 
        message: "Unknown payment status" 
      }
    end
  end
end