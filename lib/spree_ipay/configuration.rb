# frozen_string_literal: true

module SpreeIpay
  class Configuration
    class << self
      def preferences
        @preferences ||= default_preferences
      end

      def default_preferences
        {
          vendor_id: nil,
          secret_key: nil,
          live_mode: false,
          test_mode: true,
          currency: 'KES',
          api_endpoint: 'https://payments.ipayafrica.com/v3/ke',
          callback_url: nil,
          return_url: nil,
          # Channel defaults
          mpesa: true,
          bonga: false,
          airtel: false,
          equity: false,
          mobilebanking: false,
          creditcard: false,
          unionpay: false,
          mvisa: false,
          vooma: false,
          pesalink: false,
          autopay: false
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
