require 'rspec'
require 'webmock/rspec'
require 'ffaker'
require 'pry-byebug'
require 'active_support/core_ext/hash/indifferent_access'

# Mock Spree modules
module Spree
  class Base
    def self.table_name_prefix; 'spree_'; end
  end

  class Order < Base
    def initialize(attributes = {})
      attributes.each { |k, v| public_send("#{k}=", v) }
    end

    def self.find_by_number(number)
      new(number: number)
    end

    attr_accessor :number, :total, :email, :state

    def complete!; true; end
  end

  class PaymentMethod < Base; end

  class PaymentMethod::Ipay < PaymentMethod
    def self.find(id); new; end

    def preferred_vendor_id; 'demo'; end
    def preferred_hash_key; 'demoCHANGED'; end
    def preferred_test_mode; true; end
  end

  class IpaySource < Base
    attr_accessor :phone, :vendor_id, :transaction_id

    def save; true; end
  end
end

# Mock ActionController
module ActionController
  class Base
    def self.before_action(*); end
    def self.helper_method(*); end
    def self.skip_before_action(*); end

    def params
      @params ||= {}.with_indifferent_access
    end

    def params=(params)
      @params = params.with_indifferent_access
    end

    def render(options = {})
      @response ||= Response.new
      @response.body = options[:plain] if options.is_a?(Hash) && options.key?(:plain)
      @response
    end

    def redirect_to(*)
      @response ||= Response.new
      @response.status = 302
      @response
    end

    def response
      @response ||= Response.new
    end

    class Response
      attr_accessor :status, :body

      def initialize
        @status = 200
        @body = ""
      end
    end
  end
end

RSpec.configure do |config|
  config.mock_with :rspec
  config.order = :random

  # Print test names
  config.formatter = :documentation

  # Helper method to create a test controller
  config.include(Module.new do
    def setup_controller(controller_class, params = {})
      controller = controller_class.new
      controller.params = params
      controller
    end
  end)

  # Add support for testing controllers
  config.include(Module.new do
    def get(action, params: {}, session: nil, format: nil)
      controller = described_class.new
      controller.params = params
      controller.public_send(action)
      controller.response
    end
  end, type: :controller)
end

# Configure WebMock to allow local requests
WebMock.disable_net_connect!(allow_localhost: true)
