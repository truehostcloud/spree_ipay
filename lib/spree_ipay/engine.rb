module SpreeIpay
  class Engine < ::Rails::Engine
    engine_name 'spree_ipay'

    config.autoload_paths += %W[#{config.root}/lib]
    config.autoload_paths += %W[#{config.root}/app/models]

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare(&method(:activate).to_proc)

    initializer 'spree_ipay.assets' do |app|
      app.config.assets.precompile += %w[spree/backend/ipay.js]
    end

    initializer 'spree_ipay.register_payment_method', after: 'spree.register.payment_methods' do |app|
      Rails.application.config.after_initialize do
        if defined?(Spree::PaymentMethod) && defined?(Spree::PaymentMethod::Ipay) && !app.config.spree.payment_methods.include?(Spree::PaymentMethod::Ipay)
          app.config.spree.payment_methods << Spree::PaymentMethod::Ipay
        end
      end
    end
  end
end
