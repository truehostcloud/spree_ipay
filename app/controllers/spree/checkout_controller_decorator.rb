module Spree
  # Decorates the Spree::CheckoutController to add iPay payment processing functionality.
  # Handles the payment form submission and redirection to iPay's payment page.
  # Manages the payment flow during the checkout process.
  module CheckoutControllerDecorator
    def self.prepended(base)
      base.before_action :log_checkout_state, only: [:update]
      base.before_action :handle_ipay_redirect, only: [:update]
      base.before_action :set_request_variant
    end
    
    def log_checkout_state
      # No logging needed
    end

    # Set request variant based on format
    def set_request_variant
      request.variant = :api if request.format.json?
    end

    def handle_ipay_redirect
      log_prefix = '[IPAY_CHECKOUT_DEBUG] [REDIRECT_HANDLER]'
  
      # Log all parameters for debugging
      Rails.logger.info "#{log_prefix} ===== START HANDLE_IPAY_REDIRECT ====="
      Rails.logger.info "#{log_prefix} Current state: #{params[:state]}"
      Rails.logger.info "#{log_prefix} Params: #{params.to_unsafe_h.except(:controller, :action, :order).inspect}"
      Rails.logger.info "#{log_prefix} Session: #{session.to_hash.slice(:order_id, :access_token, :guest_token, :ipay_phone_number).inspect}"
  
      # Log current order state
      if @order
        Rails.logger.info "#{log_prefix} Order state: #{@order.state}"
        Rails.logger.info "#{log_prefix} Order number: #{@order.number}"
        Rails.logger.info "#{log_prefix} Order total: #{@order.total}"
        Rails.logger.info "#{log_prefix} Order payments: #{@order.payments.map { |p| "#{p.id}:#{p.state}:#{p.amount}" }.join(', ')}"
      else
        Rails.logger.error "#{log_prefix} NO ORDER FOUND IN SESSION"
      end
      
      begin
        # Get payment method and phone number during payment state
        if params[:state] == "payment"
          Rails.logger.info "#{log_prefix} Processing payment state"
          payment_params = params.dig(:order, :payments_attributes, 0) || {}
          Rails.logger.debug "#{log_prefix} Raw payment params: #{payment_params.inspect}"
          
          # Store payment method ID if present
          if payment_method_id = payment_params[:payment_method_id]
            Rails.logger.info "#{log_prefix} Storing payment method ID in session: #{payment_method_id}"
            session[:selected_payment_method_id] = payment_method_id
          end
          
          # Store phone number if present
          if phone = payment_params.dig(:source_attributes, :phone)
            Rails.logger.info "#{log_prefix} Storing phone number in session: #{phone}"
            session[:ipay_phone_number] = phone
          end
          
          # Log the current session state (debug level to avoid log spam)
          Rails.logger.debug "#{log_prefix} Session state: #{session.to_hash.except('session_id', '_csrf_token').inspect}"
          return # Return early for payment state
        end

        # Process iPay payment during confirm state
        if params[:state] == "confirm" && @order.payments.any?
          Rails.logger.info "#{log_prefix} Processing confirm state for order #{@order.number}"
          payment = @order.payments.last
          ipay_method = payment.payment_method
          
          Rails.logger.debug "#{log_prefix} Payment method details - Type: #{ipay_method.class.name}, ID: #{ipay_method.id}"
          
          # Skip if not an iPay payment method
          unless ipay_method.is_a?(Spree::PaymentMethod::Ipay)
            error_msg = "Payment method is not an iPay method (got: #{ipay_method.class.name})"
            Rails.logger.warn "#{log_prefix} #{error_msg}"
            return 
          end
          
          # Get phone from session or order
          phone = session[:ipay_phone_number] || @order.bill_address&.phone
          
          Rails.logger.info "#{log_prefix} Using phone number: #{phone.present? ? phone[0..3] + '******' + phone[-2..-1] : 'NONE'}"
          
          # Validate required fields
          if phone.blank?
            error_msg = 'Phone number is required for iPay payment'
            Rails.logger.error "#{log_prefix} #{error_msg}"
            raise error_msg 
          end

          respond_to do |format|
            format.html do
              # Generate and render the iPay form immediately
              form_html = generate_ipay_form_html(payment, phone, ipay_method)
              
              # Log form details for debugging
              form_preview = form_html.length > 200 ? form_html[0..200] + '...' : form_html
              Rails.logger.debug "[IPAY_CHECKOUT_DEBUG] [FORM_HTML] Form preview (first 200 chars): #{form_preview}"
              
              # Log full form to a separate file for detailed debugging
              File.open(Rails.root.join('log', 'ipay_form_debug.html'), 'w') do |f|
                f.puts "<!-- Form generated at: #{Time.current} -->"
                f.puts form_html
              end
              Rails.logger.debug "[IPAY_CHECKOUT_DEBUG] [FORM_HTML] Full form written to: log/ipay_form_debug.html"
              
              render html: form_html.html_safe, layout: 'spree/layouts/checkout'
            end
            format.json do
              render json: {
                status: 'success',
                next_step: 'confirm',
                form_html: generate_ipay_form_html(payment, phone, ipay_method)
              }
            end
          end
          return false # Prevent further processing
        end
      rescue => e
        Rails.log.error("[IPAY_CHECKOUT_ERROR] [REDIRECT_HANDLER] Error in handle_ipay_redirect: #{e.class} - #{e.message}")
        Rails.log.debug("[IPAY_CHECKOUT_DEBUG] [REDIRECT_HANDLER] Backtrace: #{e.backtrace.first(5).join("\n")}")
        
        error_message = if Rails.env.development?
          "#{e.class}: #{e.message}"
        else
          'Unable to process payment. Please try again.'
        end
        
        respond_to do |format|
          format.html { redirect_to checkout_state_path(@order.state), error: error_message }
          format.json { render json: { status: 'error', message: error_message }, status: :unprocessable_entity }
        end
      end
    rescue StandardError => e
      respond_to do |format|
        format.html do
          redirect_to checkout_state_path(:payment), error: "Payment processing failed: #{e.message}"
        end
        format.json do
          render json: {
            status: 'error',
            message: "Payment processing failed: #{e.message}",
            errors: [e.message]
          }, status: :unprocessable_entity
        end
      end
    end

    def generate_ipay_form_html(payment, phone, ipay_method)
      log_prefix = '[IPAY_CHECKOUT_DEBUG] [FORM_GENERATION]'
  
      # Log method entry with parameters
      Rails.logger.info "#{log_prefix} ===== START FORM GENERATION ====="
      Rails.logger.info "#{log_prefix} Order: #{payment.order.number}"
      Rails.logger.info "#{log_prefix} Payment ID: #{payment.id}, State: #{payment.state}"
      Rails.logger.info "#{log_prefix} Phone: #{phone}"
      Rails.logger.info "#{log_prefix} iPay Method ID: #{ipay_method.id}"
  
      # Log payment method details
      begin
        Rails.logger.info "#{log_prefix} Payment Method Details:"
        Rails.logger.info "#{log_prefix}   - Type: #{ipay_method.class.name}"
        Rails.logger.info "#{log_prefix}   - ID: #{ipay_method.id}"
        Rails.logger.info "#{log_prefix}   - Test Mode: #{ipay_method.preferred_test_mode}"
        Rails.logger.info "#{log_prefix}   - Vendor ID: #{ipay_method.preferred_vendor_id}"
        Rails.logger.info "#{log_prefix}   - Callback URL: #{ipay_method.preferred_callback_url}"
        Rails.logger.info "#{log_prefix}   - Return URL: #{ipay_method.preferred_return_url}"
      rescue => e
        Rails.logger.error "#{log_prefix} Error logging payment method details: #{e.message}"
      end
      
      begin
        # Get required values from payment method preferences
        live = ipay_method.preferred_test_mode ? '0' : '1'
        oid = payment.order.number
        inv = "#{payment.order.number}#{Time.now.to_i}" # unique invoice
        # Round up the amount to the nearest integer for iPay
        ttl = payment.amount.ceil.to_s
        eml = payment.order.email
        vid = ipay_method.preferred_vendor_id.presence || ''
        curr = ipay_method.preferred_currency.presence || 'KES'
        p1 = ""
        p2 = ""
        p3 = ""
        p4 = ""
        cbk = ipay_method.preferred_callback_url.presence || "https://example.com/ipay/callback"
        cst = "1"
        crl = "2"

        Rails.logger.info "#{log_prefix} Form parameters - live: #{live}, oid: #{oid}, ttl: #{ttl}, vid: #{vid}, curr: #{curr}"

        # Generate the hash with the phone number
        Rails.logger.info "#{log_prefix} Generating signature hash"
        hsh = ipay_method.ipay_signature_hash(payment, phone)
        Rails.logger.info "#{log_prefix} Generated hash: #{hsh}"

      # Prepare iPay parameters - must match the exact order and parameters used in hash generation
      ipay_params = {
        'live' => live,
        'oid' => oid,
        'inv' => inv,
        'ttl' => ttl,
        'tel' => phone || '0700000000',
        'eml' => eml,
        'vid' => vid,
        'curr' => curr,
        'p1' => p1,
        'p2' => p2,
        'p3' => p3,
        'p4' => p4,
        'cbk' => cbk,
        'cst' => cst,
        'crl' => crl,
        'hsh' => hsh
      }

      # Get enabled channels from payment method preferences
      enabled_channels = []
      channels = {
        mpesa: ipay_method.preferred_mpesa,
        bonga: ipay_method.preferred_bonga,
        airtel: ipay_method.preferred_airtel,
        equity: ipay_method.preferred_equity,
        mobilebanking: ipay_method.preferred_mobilebanking,
        creditcard: ipay_method.preferred_creditcard,
        unionpay: ipay_method.preferred_unionpay,
        mvisa: ipay_method.preferred_mvisa,
        vooma: ipay_method.preferred_vooma,
        pesalink: ipay_method.preferred_pesalink,
        autopay: ipay_method.preferred_autopay
      }

      # Log channel status
      channels.each do |channel, enabled|
        ipay_params[channel.to_s] = enabled ? '1' : '0'
        enabled_channels << channel.to_s if enabled
      end

      # Log enabled channels for debugging
      if enabled_channels.any?
        Rails.logger.info "[IPAY_CHECKOUT_DEBUG] [FORM_GENERATION] Enabled payment channels: #{enabled_channels.join(', ')}"
      else
        Rails.logger.warn "[IPAY_CHECKOUT_DEBUG] [FORM_GENERATION] No payment channels enabled! Using default channels."
        # Fallback to default channels if none enabled
        %w[mpesa airtel equity mobilebanking creditcard].each do |ch|
          ipay_params[ch] = '1'
        end
      end

      # Generate the form HTML with full-page flexible layout and improved button positioning
      begin
        form_html = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Redirecting to iPay</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <style>
            @keyframes spin {
              to { transform: rotate(360deg); }
            }
            .animate-spin {
              animation: spin 1s linear infinite;
            }
            #error-message {
              display: none;
              color: #dc2626;
              background-color: #fee2e2;
              padding: 1rem;
              border-radius: 0.5rem;
              margin-top: 1rem;
              font-family: monospace;
              white-space: pre-wrap;
              text-align: left;
            }
          </style>
        </head>
        <body class="bg-gradient-to-br from-blue-100 to-gray-100 flex items-center justify-center min-h-screen w-full p-4 sm:p-6">
          <div class="bg-white rounded-xl shadow-xl w-full max-w-3xl mx-auto p-6 sm:p-8 flex flex-col justify-center space-y-6">
            <div id="loading" class="flex flex-col items-center space-y-4">
              <div class="flex justify-center">
                <svg class="animate-spin h-14 w-14 text-blue-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
              </div>
              <h2 class="text-3xl sm:text-4xl font-extrabold text-gray-800 text-center">Redirecting to iPay</h2>
              <p class="text-gray-600 text-lg sm:text-xl text-center">Please wait while we securely redirect you to the payment page.</p>
              <p class="text-sm sm:text-base text-gray-500 text-center">If you are not redirected automatically, please click the button below.</p>
            </div>
            
            <div id="debug-info" class="hidden bg-gray-100 p-4 rounded-lg text-sm text-gray-700 font-mono">
              <h3 class="font-bold mb-2">Debug Information:</h3>
              <pre>#{JSON.pretty_generate(ipay_params)}</pre>
            </div>
            
            <form id="ipay-payment-form" action="https://payments.ipayafrica.com/v3/ke" method="post" class="flex flex-col items-center space-y-4">
              #{ipay_params.map { |k, v| "<input type='hidden' name='#{k}' value='#{ERB::Util.html_escape(v)}'>" }.join("\n")}
              
              <div class="flex space-x-4">
                <button type="submit" class="bg-blue-600 text-white font-semibold py-2 px-6 rounded-md hover:bg-blue-700 transition duration-300">
                  Proceed to Payment
                </button>
                <button type="button" onclick="toggleDebug()" class="bg-gray-200 text-gray-700 font-semibold py-2 px-4 rounded-md hover:bg-gray-300 transition duration-300">
                  Debug Info
                </button>
              </div>
              
              <div id="form-status" class="text-sm text-gray-500"></div>
            </form>
            
            <div id="error-message" class="hidden"></div>
            
            <script>
              function toggleDebug() {
                const debugInfo = document.getElementById('debug-info');
                debugInfo.classList.toggle('hidden');
              }
              
              function showError(message) {
                const errorDiv = document.getElementById('error-message');
                const statusDiv = document.getElementById('form-status');
                const loadingDiv = document.getElementById('loading');
                
                statusDiv.textContent = 'Error: ' + message;
                statusDiv.className = 'text-sm text-red-600';
                errorDiv.textContent = message;
                errorDiv.style.display = 'block';
                loadingDiv.style.display = 'none';
                
                console.error('iPay Form Error:', message);
              }
              
              document.addEventListener('DOMContentLoaded', function() {
                const form = document.getElementById('ipay-payment-form');
                const statusDiv = document.getElementById('form-status');
                
                // Try to submit the form automatically
                setTimeout(function() {
                  try {
                    statusDiv.textContent = 'Submitting form...';
                    form.submit();
                  } catch (error) {
                    showError('Auto-submit failed: ' + error.message);
                  }
                }, 1000);
                
                // Manual form submission handler
                form.addEventListener('submit', function(e) {
                  e.preventDefault();
                  try {
                    statusDiv.textContent = 'Processing...';
                    setTimeout(function() {
                      form.submit();
                    }, 300);
                  } catch (error) {
                    showError('Form submission failed: ' + error.message);
                  }
                });
              });
            </script>
          </div>
        </body>
        </html>
      HTML
      
        # Log form generation success
        Rails.logger.info "[IPAY_CHECKOUT_DEBUG] [FORM_GENERATION] Form generated successfully"
        return form_html
        
      rescue StandardError => e
        error_msg = "Error generating iPay form: #{e.message}"
        Rails.logger.error "[IPAY_CHECKOUT_ERROR] #{error_msg}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Return error page
        return <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Payment Error</title>
            <script src="https://cdn.tailwindcss.com"></script>
          </head>
          <body class="bg-gray-100 flex items-center justify-center min-h-screen p-4">
            <div class="bg-white rounded-lg shadow-lg p-8 max-w-md w-full">
              <div class="text-center">
                <div class="text-red-500 text-5xl mb-4">⚠️</div>
                <h1 class="text-2xl font-bold text-gray-800 mb-2">Payment Error</h1>
                <p class="text-gray-600 mb-6">We encountered an error while processing your payment request.</p>
                #{Rails.env.development? ? "<p class=\"text-red-500 text-sm font-mono mb-4 bg-gray-100 p-3 rounded\">#{CGI.escapeHTML(error_msg)}</p>" : ''}
                <div class="space-y-3">
                  <a href="/checkout/payment" class="block w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-4 rounded-md text-center transition duration-200">
                    Return to Payment
                  </a>
                  <a href="/cart" class="block text-blue-600 hover:text-blue-800 text-sm font-medium text-center">
                    Back to Cart
                  </a>
                </div>
              </div>
            </div>
          </body>
          </html>
        HTML
      end
      rescue StandardError => e
        Rails.logger.error "[IPAY_CHECKOUT_ERROR] [FORM_GENERATION] Error: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
        raise "Error generating payment form: #{e.message}"
      end
    end
    # Override update action to handle JSON responses
    def update
      if @order.update_from_params(params, permitted_checkout_attributes, request.headers.env)
        respond_to do |format|
          format.html do
            if @order.next
              redirect_to checkout_state_path(@order.state)
            else
              redirect_to checkout_state_path(@order.state)
            end
          end
          
          format.json do
            if @order.next
              # Get the next state after the transition
              next_state = @order.state
              
              # Prepare response data
              response_data = {
                status: 'success',
                next_step: next_state,
                order: {
                  number: @order.number,
                  state: @order.state,
                  total: @order.total.to_f,
                  payment_state: @order.payment_state,
                  shipment_state: @order.shipment_state
                },
                payment_required: @order.payment_required?,
                checkout_steps: @order.checkout_steps,
                current_step: next_state,
                next_step_url: next_step_url_for(@order, next_state)
              }
              
              # Add payment info if in payment state
              if next_state == 'payment' && @order.payments.any?
                payment = @order.payments.last
                response_data[:payment] = {
                  id: payment.id,
                  number: payment.number,
                  state: payment.state,
                  amount: payment.amount.to_f,
                  payment_method_id: payment.payment_method_id,
                  payment_method_type: payment.payment_method&.type
                }
              end
              
              render json: response_data
            else
              render json: {
                status: 'error',
                errors: @order.errors.messages,
                message: @order.errors.full_messages.to_sentence
              }, status: :unprocessable_entity
            end
          end
        end
      else
        respond_to do |format|
          format.html { render :edit }
          format.json do
            render json: {
              status: 'error',
              errors: @order.errors.messages,
              message: @order.errors.full_messages.to_sentence,
              validation_errors: @order.errors.full_messages
            }, status: :unprocessable_entity
          end
        end
      end
    end
    
    private
    
    def next_step_url_for(order, next_step)
      return unless next_step
      
      case next_step
      when 'address'
        checkout_state_path('address')
      when 'delivery'
        checkout_state_path('delivery')
      when 'payment'
        checkout_state_path('payment')
      when 'confirm'
        checkout_state_path('confirm')
      when 'complete'
        order_path(order, order_token: order.guest_token)
      end
    end
  end
end

::Spree::CheckoutController.prepend Spree::CheckoutControllerDecorator
