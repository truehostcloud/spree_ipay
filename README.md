# Spree iPay Payment Gateway Integration

This gem integrates the iPay payment gateway with your Spree e-commerce store, enabling secure online payments through iPay's payment processing system.

## Features

- Seamless integration with Spree e-commerce
- Secure payment processing through iPay
- Support for multiple payment methods
- Easy configuration and setup
- Callback handling for payment status updates

## Prerequisites

- Ruby (version specified in your Gemfile)
- Rails (version specified in your Gemfile)
- Spree e-commerce platform
- iPay merchant account and API credentials

## Installation

1. Add this line to your application's Gemfile:

```ruby
gem 'spree_ipay', path: 'path/to/this/gem'  # For local development
# OR
gem 'spree_ipay', github: 'your-repo/spree_ipay'  # If hosted on GitHub
```

2. Install the gem:

```bash
bundle install
```

3. Run the installer:

```bash
bundle exec rails g spree_ipay:install
```

4. Run migrations:

```bash
bundle exec rails db:migrate
```

## Configuration

1. Navigate to your Spree admin panel
2. Go to Configuration > Payment Methods
3. Click "New Payment Method"
4. Select "Spree::PaymentMethod::Ipay" as the provider
5. Fill in the required fields:
   - Name: iPay
   - Description: Pay with iPay
   - Active: Check to enable
   - Display on: Both (or as needed)
   - Auto-capture: As per your preference
   - Test mode: Check for testing, uncheck for production
   - Merchant ID: Your iPay merchant ID
   - Merchant Key: Your iPay merchant key
   - Hash Key: Your iPay hash key
   - Environment: test or production