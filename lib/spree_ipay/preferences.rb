module SpreeIpay
  class Preferences
    attr_accessor :live_mode, :vendor_id, :secret_key, :api_endpoint,
                  :callback_url, :return_url, :currency,
                  :mpesa, :bonga, :airtel, :equity, :mobilebanking,
                  :creditcard, :unionpay, :mvisa, :vooma, :pesalink, :autopay

    def initialize
      # Load from environment variables with defaults
      @live_mode = ENV['IPAY_LIVE_MODE'] ? true : false
      @vendor_id = ENV['IPAY_VENDOR_ID'] || ''
      @secret_key = ENV['IPAY_SECRET_KEY'] || ''
      @api_endpoint = ENV['IPAY_API_ENDPOINT'] || 'https://payments.ipayafrica.com/v3/ke'
      @callback_url = ENV['IPAY_CALLBACK_URL']
      @return_url = ENV['IPAY_RETURN_URL']
      @currency = ENV['IPAY_CURRENCY'] || 'KES'

      # Channel preferences
      @mpesa = ENV['IPAY_MPESA'] ? true : false
      @bonga = ENV['IPAY_BONGA'] ? true : false
      @airtel = ENV['IPAY_AIRTEL'] ? true : false
      @equity = ENV['IPAY_EQUITY'] ? true : false
      @mobilebanking = ENV['IPAY_MOBILEBANKING'] ? true : false
      @creditcard = ENV['IPAY_CREDITCARD'] ? true : false
      @unionpay = ENV['IPAY_UNIONPAY'] ? true : false
      @mvisa = ENV['IPAY_MVISA'] ? true : false
      @vooma = ENV['IPAY_VOOMA'] ? true : false
      @pesalink = ENV['IPAY_PESALINK'] ? true : false
      @autopay = ENV['IPAY_AUTOPAY'] ? true : false
    end

    def self.current
      @current ||= new
    end

    def self.[](name)
      current.send(name)
    end

    def self.[]=(name, value)
      current.send("#{name}=".to_sym, value)
    end
  end
end
