# Spree iPay Payment Gateway Extension

This gem integrates the iPay payment gateway with your Spree Commerce store, enabling secure online payments via iPay's platform.

---

## Features

- Seamless Spree integration (standalone extension)
- Secure C2B (customer-to-business) payment flow with HMAC SHA1 callback signature verification
- Handles iPay callback and payment state transitions
- Minimal database footprint: only creates payment method and source tables
- Easy installation and migration

---

## Prerequisites

- Ruby (see your Gemfile for version)
- Rails (see your Gemfile for version)
- Spree Commerce (any supported version)
- iPay merchant account (get your Vendor ID and Hash Key from iPay)

---

## Installation

1. **Add the gem to your application's Gemfile:**
   ```ruby
   gem 'spree_ipay', path: 'path/to/this/gem'  # Local development
   # OR
   gem 'spree_ipay', github: 'your-repo/spree_ipay'  # If hosted on GitHub
   ```
2. **Install the gem:**
   ```bash
   bundle install
   ```
3. **Install migrations from the extension:**
   ```bash
   bundle exec rails railties:install:migrations
   ```
   This copies all iPay-related migrations from the extension to your main app.
4. **Run database migrations:**
   ```bash
   bundle exec rails db:migrate
   ```

---

## Configuration

1. **In Spree Admin:**

   - Go to `Configuration > Payment Methods`
   - Click "New Payment Method"
   - Choose `Spree::PaymentMethod::Ipay` as the provider
   - Fill in the required fields:
     - Name: iPay
     - Description: Pay with iPay
     - Active: Check to enable
     - Display on: Both (or as needed)
     - Test mode: Check for testing, uncheck for production
     - Vendor ID: Your iPay Vendor ID
     - Hash Key: Your iPay Hash Key
     - Currency: e.g., KES

2. **Callback/Return URLs:**
   - Set your callback URL in iPay dashboard to:
     ```
     https://your-store.com/ipay/confirm
     ```
   - Ensure your endpoint is accessible and matches what you configure in Spree preferences.

---

## Security: HMAC Signature Verification

- This extension verifies iPay callback authenticity using HMAC SHA1, as per iPay's 2025 C2B documentation.
- **Do not disable this check in production.**
- Ensure your hash key in Spree matches the one in your iPay merchant dashboard.

---

## Upgrading or Reinstalling

- If you update the extension, re-run:
  ```bash
  bundle exec rails railties:install:migrations
  bundle exec rails db:migrate
  ```
- Remove any old iPay migrations from your main app if you move to using the extension.

---

## Troubleshooting

- If callbacks fail HMAC verification, double-check:
  - Your hash key (test vs. live)
  - All callback parameters are present and ordered as per iPay docs
  - Your callback URL is accessible from the public internet
- For test mode, ensure you use iPay's test credentials and environment.

---

## Uninstallation

- Remove the gem from your Gemfile
- Remove the iPay migrations from your main app if no longer needed
- Run `rails db:migrate` to drop iPay-specific tables if desired

---

## Support

For help, open an issue in this repository or contact your integration partner.

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
