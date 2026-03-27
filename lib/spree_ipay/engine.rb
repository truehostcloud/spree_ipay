module SpreeIpay
  class Engine < ::Rails::Engine
    require 'spree/core'

    engine_name 'spree_ipay'
    isolate_namespace Spree

    config.autoload_paths << root.join('lib')

    config.generators do |g|
      g.test_framework :rspec
    end

    initializer 'spree_ipay.assets' do |app|
      next unless app.config.respond_to?(:assets)

      app.config.assets.precompile += %w[
        spree/frontend/spree_ipay.js
        spree/frontend/checkout/payment/ipay.js
        spree/backend/spree_ipay.js
        spree/frontend/spree_ipay.css
        spree/backend/spree_ipay.css
      ]
    end

    config.after_initialize do |app|
      app.config.spree.payment_methods ||= []
      app.config.spree.payment_methods << Spree::PaymentMethod::Ipay unless app.config.spree.payment_methods.include?(Spree::PaymentMethod::Ipay)
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')).sort.each do |decorator|
        Rails.configuration.cache_classes ? require(decorator) : load(decorator)
      end
    end

    config.to_prepare(&method(:activate).to_proc)
  end
end
