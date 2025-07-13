# frozen_string_literal: true

# Rate limiting for API endpoints
Rails.application.config.after_initialize do
  # Only enable in production or if explicitly enabled in development/test
  if Rails.env.production? || ENV['ENABLE_RACK_ATTACK'] == 'true'
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
    Rack::Attack.enabled = false
  end
end
