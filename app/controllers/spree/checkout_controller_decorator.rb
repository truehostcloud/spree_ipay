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
      # Get phone number and store in session during payment state
      if params[:state] == "payment"
        phone = params.dig(:order, :payments_attributes, 0, :source_attributes, :phone)
        session[:ipay_phone_number] = phone if phone.present?
      end

      # Generate form and redirect during confirm state
      if params[:state] == "confirm" && @order.payments.last&.payment_method&.is_a?(Spree::PaymentMethod::Ipay)
        payment = @order.payments.last
        ipay_method = payment.payment_method

        # Generate iPay form HTML
        form_html = generate_ipay_form_html(payment, session[:ipay_phone_number], ipay_method)

        respond_to do |format|
          format.html do
            # Render the form using content_type for security
            render inline: form_html, content_type: 'text/html', layout: 'spree/layouts/checkout'
          end
          format.json do
            render json: {
              status: 'success',
              next_step: 'confirm',
              form_html: form_html
            }
          end
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
      # Get required values from payment method preferences
      live = ipay_method.preferred_test_mode ? '0' : '1'
      oid = payment.order.number
      inv = "#{payment.order.number}#{Time.now.to_i}" # unique invoice
      ttl = (payment.amount.to_f * 100).to_i.to_s # Amount in cents
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

      # Generate the hash with the phone number
      hsh = ipay_method.ipay_signature_hash(payment, phone)

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

      # Add channel parameters based on preferences
      %i[
        mpesa bonga airtel equity mobilebanking
        creditcard unionpay mvisa vooma pesalink autopay
      ].each do |channel|
        ipay_params[channel.to_s] = ipay_method.preferences["#{channel}"] ? '1' : '0'
      end

      # Generate the form HTML with full-page flexible layout and improved button positioning
      <<~HTML
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
          </style>
        </head>
        <body class="bg-gradient-to-br from-blue-100 to-gray-100 flex items-center justify-center min-h-screen w-full p-4 sm:p-6">
          <div class="bg-white rounded-xl shadow-xl w-full max-w-3xl mx-auto p-6 sm:p-8 flex flex-col justify-center space-y-6">
            <div class="flex justify-center">
              <svg class="animate-spin h-14 w-14 text-blue-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
            </div>
            <h2 class="text-3xl sm:text-4xl font-extrabold text-gray-800 text-center">Redirecting to iPay</h2>
            <p class="text-gray-600 text-lg sm:text-xl text-center">Please wait while we securely redirect you to the payment page.</p>
            <p class="text-sm sm:text-base text-gray-500 text-center">If you are not redirected automatically, please click the button below.</p>
            <form id="ipay-payment-form" action="#{ipay_method.preferred_test_mode ? 'https://payments.ipayafrica.com/v3/ke' : 'https://payments.ipayafrica.com/v3/ke'}" method="post" class="flex justify-center">
              #{ipay_params.map { |k, v| "<input type='hidden' name='#{k}' value='#{ERB::Util.html_escape(v)}'>" }.join("\n")}
              <button type="submit" class="bg-blue-600 text-white font-semibold py-2 px-4 rounded-md hover:bg-blue-700 transition duration-300">Proceed to Payment</button>
            </form>
            <script>
              document.addEventListener('DOMContentLoaded', function() {
                setTimeout(function() {
                  document.getElementById('ipay-payment-form').submit();
                }, 1000);
              });
            </script>
          </div>
        </body>
        </html>
      HTML
    rescue StandardError => e
      raise "Error generating payment form: #{e.message}"
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
