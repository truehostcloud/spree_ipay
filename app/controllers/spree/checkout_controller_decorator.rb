module Spree
  # Decorates the Spree::CheckoutController to add iPay payment processing functionality.
  # Handles the payment form submission and redirection to iPay's payment page.
  # Manages the payment flow during the checkout process.
  module CheckoutControllerDecorator
    def self.prepended(base)
      base.before_action :handle_ipay_redirect, only: [:update]
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

        # Render the form using content_type for security
        render inline: form_html, content_type: 'text/html', layout: 'spree/layouts/checkout'
      end
    rescue StandardError => e
      redirect_to checkout_state_path(:payment), error: "Payment processing failed: #{e.message}"
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
  end
end

::Spree::CheckoutController.prepend Spree::CheckoutControllerDecorator
