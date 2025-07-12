# Start Elastic APM if enabled
if ENV['ELASTIC_APM_ENABLED'] == 'true' && defined?(ElasticAPM)
  # Configure APM with secure defaults
  ElasticAPM.start(
    app: Rails.application,
    config_file: Rails.root.join('config', 'elastic_apm.yml')
  )

  # Add a filter to remove any sensitive data from the APM payload
  ElasticAPM::Agent.add_filter do |payload|
    # Remove any sensitive headers
    if payload.dig(:context, :request, :headers)
      payload[:context][:request][:headers] = {}
    end
    
    # Remove any sensitive response data
    if payload.dig(:context, :response, :headers)
      payload[:context][:response][:headers] = {}
    end
    
    payload
  end
  
  # Ensure APM is properly stopped when the app shuts down
  at_exit { ElasticAPM.stop }
end

# Custom logger that forwards to both Rails and Elastic APM
module Spree
  module Ipay
    class Logger
      def self.debug(message, order_id = nil)
        return unless defined?(ElasticAPM)
        
        # Add to APM transaction
        if (transaction = ElasticAPM.current_transaction)
          transaction.set_label(:order_id, order_id) if order_id
          transaction.set_custom_context(
            message: message,
            timestamp: Time.current.iso8601,
            source: 'ipay_integration'
          )
        end
        
        # Also log to Rails in development
        Rails.logger.debug("[IPAY_DEBUG] #{message}") if Rails.env.development?
      end
      
      def self.error(exception, order_id = nil)
        return unless defined?(ElasticAPM)
        
        # Report error to APM
        ElasticAPM.report(exception, 
          context: build_context(order_id),
          handled: true
        )
        
        # Also log to Rails in development
        if Rails.env.development? && exception
          Rails.logger.error("[IPAY_ERROR] #{exception.message}\n#{exception.backtrace.join("\n")}")
        end
      end
      
      private
      
      def self.build_context(order_id)
        return unless defined?(ElasticAPM)
        
        context = {
          tags: { source: 'ipay_integration' },
          custom: { timestamp: Time.current.iso8601 }
        }
        
        context[:user] = { id: order_id } if order_id
        context
      end
    end
  end
end
