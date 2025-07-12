module Spree
  class IpayController < Spree::StoreController
    protect_from_forgery except: :callback
    
    # iPay callback endpoint - handles both test and live environments
    # All callback logic is now handled by Spree::GatewayCallbacksController
    
    # Interactive checkout method for redirecting to iPay
    def interactive_checkout
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
      redirect_to checkout_state_path(@order&.state || :cart), 
                  alert: "An error occurred while processing your payment. Please try again."
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
        
        verified_status == actual_status
      rescue => e
        false
      end
    end
    
    # Build IPN verification URL
    def build_ipn_url(vendor_id, transaction_data)
      # Build the URL for IPN verification as per iPay documentation
      params = {
        id: vendor_id,
        ivm: transaction_data[:invoice],
        qwh: transaction_data[:qwh],
        afd: transaction_data[:afd],
        poi: transaction_data[:poi],
        uyt: transaction_data[:uyt],
        ifd: transaction_data[:ifd]
      }.compact
      
      "https://www.ipayafrica.com/ipn/?" + params.to_query
    end
    
    # Make IPN verification request
    def make_ipn_request(url)
      uri = URI.parse(url)
      
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
      
      order
    end
    
    def find_payment_for_order(order)
      # Find only iPay payments
      ipay_payments = order.payments
                          .where(payment_method: Spree::PaymentMethod::Ipay)
                          .order(created_at: :desc)
                          .to_a
      
      # Return the most recent payment if found
      return ipay_payments.first if ipay_payments.any?
      
      # No iPay payments found
      nil
    rescue => e
      Spree::Ipay::Logger.error(StandardError.new("Error finding payment for order #{order.id}: #{e.message}"), order.number)
      nil
    end
    
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
      Spree::Ipay::Logger.error(StandardError.new("Error updating payment details: #{e.message}"), order.number)
      # Don't fail the entire callback if we can't update payment details
    end
    
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
          return
        rescue => e
          Spree::Ipay::Logger.error(StandardError.new("Error completing payment: #{e.message}"), order.number)
          render json: { 
            status: 0, 
            id: transaction_data[:transaction_id], 
            message: "Failed to complete payment" 
          }
          return
        end
      end
      
      # If we get here, payment was already completed
      render json: { 
        status: 2, 
        id: transaction_data[:transaction_id], 
        message: "Duplicate" 
      }
    end
    
    def handle_pending_payment(payment, order)
      payment.started_processing! if payment.checkout?
      
      render json: { 
        status: 1, 
        id: payment.number, 
        message: "Payment pending" 
      }
    end
    
    def handle_failed_payment(payment, order)
      payment.failure! unless payment.failed?
      
      render json: { 
        status: 0, 
        id: payment.number, 
        message: "Payment failed" 
      }
    end
    
    def handle_duplicate_payment(payment, order)
      
      render json: { 
        status: 2, 
        id: payment.number, 
        message: "Duplicate payment" 
      }
    end
    
    def handle_insufficient_payment(payment, order, transaction_data)
      payment.failure! unless payment.failed?
      
      render json: { 
        status: 0, 
        id: payment.number, 
        message: "Insufficient payment amount" 
      }
    end
    
    def handle_overpayment(payment, order, transaction_data)
      payment.failure! unless payment.failed?
      
      render json: { 
        status: 0, 
        id: payment.number, 
        message: "Overpayment detected" 
      }
    end
    
    def handle_unknown_status(payment, order, status)
      payment.failure! unless payment.failed?
      
      render json: { 
        status: 0, 
        id: payment.number, 
        message: "Unknown payment status: #{status}" 
      }
    end
  end
end