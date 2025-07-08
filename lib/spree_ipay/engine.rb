module SpreeIpay
  class Engine < ::Rails::Engine
    engine_name 'spree_ipay'
    isolate_namespace Spree

    # Configure autoload paths
    config.autoload_paths += %W[
      #{config.root}/lib
      #{config.root}/app/models
    ]

    # Configure generators
    config.generators do |g|
      g.test_framework :rspec
    end

    # Add views to load paths
    initializer 'spree_ipay.add_views', after: :load_config_initializers do |app|
      # Add gem's views to the main app's view path
      app.config.paths['app/views'].unshift(config.root.join('app/views'))
      
      # Add spree views path
      config.paths['app/views'] << 'app/views/spree'
    end

    # Configure assets precompilation
    initializer 'spree_ipay.assets' do |app|
      app.config.assets.precompile += %w[spree/backend/ipay.js]
    end

    # Register the payment method
    initializer 'spree_ipay.register_payment_method', after: 'spree.register.payment_methods' do |app|
      Rails.application.config.after_initialize do
        if defined?(Spree::PaymentMethod) && defined?(Spree::PaymentMethod::Ipay) && 
           !app.config.spree.payment_methods.include?(Spree::PaymentMethod::Ipay)
          app.config.spree.payment_methods << Spree::PaymentMethod::Ipay
        end
      end
    end
    
    # Load decorators
    config.to_prepare do
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require_dependency(c) : load(c)
      end
    end
  end
end
