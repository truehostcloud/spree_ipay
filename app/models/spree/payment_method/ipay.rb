# frozen_string_literal: true

require 'erb'
require 'httparty'
require 'json'
require 'openssl'
require 'uri'

module Spree
  module Ipay
    VERSION = '1.0.10'
  end

  class PaymentMethod::Ipay < ::Spree::PaymentMethod
    include HTTParty

    CHANNEL_PREFERENCES = %i[
      mpesa bonga airtel equity mobilebanking
      creditcard unionpay mvisa vooma pesalink autopay
    ].freeze

    preference :vendor_id, :string
    preference :hash_key, :string
    preference :test_mode, :boolean, default: true
    preference :currency, :string, default: 'KES'
    preference :callback_url, :string, default: '/ipay/confirm'
    preference :return_url, :string, default: '/ipay/confirm'

    CHANNEL_PREFERENCES.each do |channel|
      preference channel, :boolean, default: (channel == :mpesa)
    end

    def self.preference_order
      [
        :vendor_id, :hash_key, :test_mode, :currency,
        :callback_url, :return_url, *CHANNEL_PREFERENCES
      ]
    end

    def self.preferences
      super.slice(*preference_order)
    end

    def partial_name
      'ipay'
    end

    def payment_profiles_supported?
      false
    end

    def payment_source_class
      Spree::IpaySource
    end

    def source_required?
      true
    end

    def auto_capture?
      false
    end

    def can_void?(payment)
      payment.pending? || payment.processing?
    end

    def can_capture?(payment)
      payment.pending? || payment.processing?
    end

    def supports?(source)
      source.nil? || source.is_a?(Spree::IpaySource)
    end

    def reusable_sources(_order)
      []
    end

    def payment_config
      Rails.cache.fetch("ipay_config_#{id}", expires_in: 1.hour) do
        {
          vendor_id: preferred_vendor_id,
          hash_key: preferred_hash_key,
          test_mode: test_mode?,
          currency: preferred_currency,
          callback_url: preferred_callback_url,
          return_url: preferred_return_url,
          channels: CHANNEL_PREFERENCES.index_with { |channel| public_send("preferred_#{channel}") }
        }
      end
    end

    def preferences=(prefs)
      super
      Rails.cache.delete("ipay_config_#{id}") if id.present?
    end

    def authorize(amount, source, options = {})
      payment = options[:originator]
      return failure_response('Payment is missing') unless payment.is_a?(Spree::Payment)

      ipay_source = ensure_source(source, payment)
      return failure_response('Phone number is required for iPay payments') unless ipay_source&.phone.present?

      payment.source = ipay_source
      payment.payment_method ||= self
      payment.amount = amount if amount.present?

      return failure_response(payment.errors.full_messages.to_sentence) unless payment.save

      store_phone_in_session(options, ipay_source.phone)
      process!(phone: ipay_source.phone, payment: payment, amount: amount, options: options)
    rescue StandardError => error
      failure_response("Authorization failed: #{error.message}")
    end

    def capture(_amount, response_code, _options = {})
      return success_response('Test mode - payment captured successfully', authorization: "TEST-#{SecureRandom.hex(8)}") if test_mode?

      success_response('Payment captured successfully', authorization: response_code)
    rescue StandardError => error
      failure_response("Capture failed: #{error.message}")
    end

    def void(response_code, _options = {})
      return success_response('Test mode - payment voided successfully', authorization: "TEST-VOID-#{SecureRandom.hex(4)}") if test_mode?

      response = cancel_payment(response_code)
      return success_response if response['status'] == 'success'

      failure_response(response['message'] || 'Payment void failed')
    rescue StandardError => error
      failure_response("Payment void failed: #{error.message}")
    end

    def process!(phone: nil, payment: nil, amount: nil, options: {})
      return failure_response('Missing required parameters') unless payment&.order && phone.present? && amount.to_f.positive?
      return failure_response('Payment configuration error') if preferred_vendor_id.blank? || preferred_hash_key.blank?

      payment.started_processing! if payment.respond_to?(:started_processing!) && payment.checkout?

      form_html = generate_ipay_form_html(payment, phone)
      store_phone_in_session(options, phone)
      options[:controller]&.session&.[]=(:ipay_form_html, form_html)

      ActiveMerchant::Billing::Response.new(
        true,
        'iPay payment initiated successfully',
        { form_html: form_html },
        authorization: payment.number,
        test: test_mode?
      )
    rescue StandardError => error
      failure_response("Payment processing failed: #{error.message}")
    end

    def generate_ipay_form_html(payment, phone = nil)
      fields = build_form_fields(payment, phone)

      form_inputs = fields.map do |key, value|
        %(<input type='hidden' name='#{ERB::Util.html_escape(key.to_s)}' value='#{ERB::Util.html_escape(value.to_s)}'>)
      end.join("\n")

      <<~HTML
        <form id='ipay_form' action='#{ERB::Util.html_escape(api_endpoint)}' method='POST'>
          #{form_inputs}
          <input type='submit' value='Pay with iPay'>
        </form>
        <script>document.getElementById('ipay_form').submit();</script>
      HTML
    end

    def ipay_signature_hash(payment, phone = nil)
      signature_payload(build_form_fields(payment, phone))
    end

    def confirm(payment, phone: nil)
      return success_response if payment.completed?

      response = process!(phone: phone || payment.source&.phone, payment: payment, amount: payment.amount, options: {})
      return response if response.success?

      failure_response(response.message)
    end

    def complete(payment)
      return success_response if payment.completed?

      status_response = check_payment_status(payment.response_code)
      return failure_response(status_response['message'] || 'Payment completion failed') unless status_response['status'] == 'success'

      payment.complete! if payment.respond_to?(:can_complete?) ? payment.can_complete? : !payment.completed?
      success_response
    rescue StandardError => error
      failure_response("Payment completion failed: #{error.message}")
    end

    def check_payment_status(transaction_id)
      return error_hash('Missing transaction reference') if transaction_id.blank?

      response = self.class.post(status_endpoint, body: status_request_params(transaction_id))
      JSON.parse(response.body)
    rescue StandardError
      error_hash('Failed to check payment status')
    end

    def cancel_payment(transaction_id)
      return error_hash('Missing transaction reference') if transaction_id.blank?

      response = self.class.post(status_endpoint, body: cancel_request_params(transaction_id))
      JSON.parse(response.body)
    rescue StandardError
      error_hash('Failed to cancel payment')
    end

    def generate_hash(payment)
      fields = build_form_fields(payment, payment.source&.phone)
      signature_payload(fields.except(:hsh))
    end

    def generate_status_hash(transaction_id)
      OpenSSL::HMAC.hexdigest('sha1', preferred_hash_key.to_s, [live_value, preferred_vendor_id.to_s, transaction_id.to_s].join)
    end

    def generate_cancel_hash(transaction_id)
      generate_status_hash(transaction_id)
    end

    def callback_url(_payment = nil)
      absolute_url(preferred_callback_url.presence || '/ipay/confirm')
    end

    def return_url(payment = nil)
      fallback = payment ? "/orders/#{payment.order.number}?order_token=#{payment.order.guest_token}" : '/ipay/confirm'
      absolute_url(preferred_return_url.presence || fallback)
    end

    def base_url
      default_host = Rails.application.routes.default_url_options[:host]
      return '' if default_host.blank?

      protocol = Rails.application.routes.default_url_options[:protocol].presence || 'https'
      "#{protocol}://#{default_host}"
    end

    def test_mode?
      ActiveModel::Type::Boolean.new.cast(preferred_test_mode)
    end

    def api_endpoint
      test_mode? ? 'https://sandbox.ipayafrica.com/v3/ke' : 'https://payments.ipayafrica.com/v3/ke'
    end

    def success_response(message = 'Success', authorization: nil)
      ActiveMerchant::Billing::Response.new(true, message, {}, authorization: authorization, test: test_mode?)
    end

    def failure_response(message = 'Failed')
      ActiveMerchant::Billing::Response.new(false, message, {}, test: test_mode?)
    end

    private

    def build_form_fields(payment, phone = nil)
      normalized_phone = normalize_phone(phone || payment.source&.phone || payment.order.bill_address&.phone || payment.order.billing_address&.phone)

      fields = {
        live: live_value,
        oid: payment.order.number.to_s,
        inv: payment.order.number.to_s,
        ttl: payment_amount_value(payment),
        tel: normalized_phone,
        eml: payment.order.email.to_s,
        vid: preferred_vendor_id.to_s,
        curr: preferred_currency.presence || 'KES',
        p1: '',
        p2: '',
        p3: '',
        p4: '',
        cbk: callback_url(payment),
        rst: return_url(payment),
        cst: '1',
        crl: '2'
      }

      CHANNEL_PREFERENCES.each do |channel|
        fields[channel] = public_send("preferred_#{channel}") ? '1' : '0'
      end

      fields[:hsh] = signature_payload(fields)
      fields
    end

    def ensure_source(source, payment)
      ipay_source = source.presence || payment.source
      return ipay_source if ipay_source.is_a?(Spree::IpaySource) && ipay_source.phone.present?

      phone = normalize_phone(payment.source&.phone || payment.order&.bill_address&.phone || payment.order&.billing_address&.phone)
      return if phone.blank?

      Spree::IpaySource.find_or_initialize_by(payment_method: self, phone: phone).tap do |record|
        record.save! if record.new_record? || record.changed?
      end
    end

    def store_phone_in_session(options, phone)
      controller = options[:controller]
      return unless controller&.respond_to?(:session) && phone.present?

      controller.session[:ipay_phone_number] = phone
    end

    def normalize_phone(phone)
      digits = phone.to_s.gsub(/\D/, '')
      return if digits.blank?
      return "254#{digits[1..]}" if digits.length == 10 && digits.start_with?('0')
      return "254#{digits}" if digits.length == 9

      digits
    end

    def payment_amount_value(payment)
      (payment.amount.to_f * 100).to_i.to_s
    end

    def signature_payload(fields)
      data_string = %i[live oid inv ttl tel eml vid curr p1 p2 p3 p4 cbk cst crl].map { |key| fields[key].to_s }.join
      OpenSSL::HMAC.hexdigest('sha1', preferred_hash_key.to_s, data_string)
    end

    def status_request_params(transaction_id)
      {
        live: live_value,
        vid: preferred_vendor_id,
        tid: transaction_id,
        hsh: generate_status_hash(transaction_id)
      }
    end

    def cancel_request_params(transaction_id)
      {
        live: live_value,
        vid: preferred_vendor_id,
        tid: transaction_id,
        hsh: generate_cancel_hash(transaction_id)
      }
    end

    def status_endpoint
      test_mode? ? 'https://sandbox.ipayafrica.com/ipn/' : 'https://www.ipayafrica.com/ipn/'
    end

    def live_value
      test_mode? ? '0' : '1'
    end

    def absolute_url(value)
      uri = URI.parse(value)
      return value if uri.host.present?
      return value if base_url.blank?

      "#{base_url}#{value.start_with?('/') ? value : "/#{value}"}"
    rescue URI::InvalidURIError
      value
    end

    def error_hash(message)
      { 'status' => 'error', 'message' => message }
    end
  end
end
