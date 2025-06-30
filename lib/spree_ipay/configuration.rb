# frozen_string_literal: true

module SpreeIpay
  class Configuration
    class << self
      def preferences
        @preferences ||= default_preferences
      end

      def default_preferences
        {
          vendor_id: ENV['IPAY_VENDOR_ID'],
          secret_key: ENV['IPAY_SECRET_KEY'],
          live_mode: ENV['IPAY_LIVE_MODE'] != 'false',
          test_mode: ENV['IPAY_TEST_MODE'] != 'false',
          currency: ENV['IPAY_CURRENCY'] || 'KES',
          api_endpoint: ENV['IPAY_API_ENDPOINT'] || 'https://payments.ipayafrica.com/v3/ke',
          callback_url: ENV['IPAY_CALLBACK_URL'],
          return_url: ENV['IPAY_RETURN_URL'],
          # Channel defaults
          mpesa: ENV['IPAY_MPESA'] != 'false',
          bonga: ENV['IPAY_BONGA'] != 'false',
          airtel: ENV['IPAY_AIRTEL'] != 'false',
          equity: ENV['IPAY_EQUITY'] != 'false',
          mobilebanking: ENV['IPAY_MOBILEBANKING'] != 'false',
          creditcard: ENV['IPAY_CREDITCARD'] != 'false',
          unionpay: ENV['IPAY_UNIONPAY'] != 'false',
          mvisa: ENV['IPAY_MVISA'] != 'false',
          vooma: ENV['IPAY_VOOMA'] != 'false',
          pesalink: ENV['IPAY_PESALINK'] != 'false',
          autopay: ENV['IPAY_AUTOPAY'] != 'false'
        }.freeze
      end

      def [](key)
        preferences[key.to_sym]
      end

      def []=(key, value)
        preferences[key.to_sym] = value
      end

      def method_missing(method_name, *args, &block)
        if method_name.to_s.end_with?('=')
          self[method_name.to_s.chomp('=')] = args.first
        else
          self[method_name]
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        method_name.to_s.end_with?('=') || preferences.key?(method_name.to_sym) || super
      end
    end
  end

  # Global preferences accessor
  def self.Preferences
    Configuration
  end
  
  # Alias for backward compatibility
  Preferences = Configuration unless defined?(Preferences)
end
