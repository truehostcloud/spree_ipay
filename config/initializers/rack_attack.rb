# frozen_string_literal: true

# Only load Rack::Attack if the gem is available
begin
  require 'rack/attack'
  
  # Rate limiting for API endpoints
  Rails.application.config.after_initialize do
    # Only enable in production or if explicitly enabled in development/test
    if defined?(Rack::Attack) && (Rails.env.production? || ENV['ENABLE_RACK_ATTACK'] == 'true')
      Rack::Attack.enabled = true
      
      # Throttle API requests to 60 requests per minute per IP
      Rack::Attack.throttle('ipay_api', limit: 60, period: 1.minute) do |req|
        if req.path.start_with?('/api/v1/ipay/') && (req.get? || req.post?)
          req.ip
        end
      end

      # Custom response for throttled requests
      Rack::Attack.throttled_responder = lambda do |env|
        now = Time.now.utc
        match_data = env['rack.attack.match_data']
        
        headers = {
          'Content-Type' => 'application/json',
          'RateLimit-Limit' => match_data[:limit].to_s,
          'RateLimit-Remaining' => '0',
          'RateLimit-Reset' => (now + (match_data[:period] - now.to_i % match_data[:period])).to_s
        }
        
        [429, headers, [
          { 
            status: 'error',
            message: 'Too many requests. Please try again later.'
          }.to_json
        ]]
      end
    else
      Rack::Attack.enabled = false if defined?(Rack::Attack)
    end
  end
rescue LoadError => e
  Rails.logger.warn("Rack::Attack not loaded: #{e.message}")
end
