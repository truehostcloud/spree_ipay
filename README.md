# Spree iPay Payment Gateway Extension

This gem integrates the iPay payment gateway with your Spree Commerce store, enabling secure online payments via iPay's platform.

---

## Features

- Seamless Spree integration (standalone extension)
- Secure C2B (customer-to-business) payment flow with HMAC SHA1 callback signature verification
- Handles iPay callback and payment state transitions
- Minimal database footprint: only creates payment method and source tables
- Easy installation and migration
- Comprehensive JSON API support
- Mobile money and card payment support
- Enhanced error handling and logging
- Payment status polling for real-time updates

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

## API Endpoints

### Check Payment Status
```
GET /api/v1/ipay/status?order_id=:order_number
```

Response:
```json
{
  "status": "success",
  "payment": {
    "id": 1,
    "state": "completed",
    "amount": "100.0",
    "payment_method_id": 1
  },
  "order": {
    "number": "R123456789",
    "state": "complete",
    "total": "100.0"
  }
}
```

### Payment Callback
```
POST /api/v1/ipay/callback
```

Expected Parameters:
```json
{
  "id": "12345",
  "ivm": "INV123",
  "qwh": "query_with_hash",
  "afd": "amount_from_database",
  "poi": "payment_options_used",
  "uyt": "unique_your_transaction",
  "ifd": "invoice_from_database"
}
```

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

## Running the Test Suite

This extension includes a full RSpec test suite. To run the tests:

1. **Install dependencies:**

   ```bash
   bundle install
   ```

2. **Set up the dummy app (if not already set up):**

   ```bash
   bundle exec rails app:template LOCATION="https://raw.githubusercontent.com/spree/spree/master/lib/generators/templates/rails/engine/dummy_template.rb" --dummy_path=spec/dummy
   ```

   Or, if you already have a `spec/dummy` app, skip this step.

3. **Run the specs:**
   ```bash
   bundle exec rspec
   ```

- All required helper files (`spec_helper.rb`, `rails_helper.rb`, and any support files) are included in the `spec/` directory of this extension.
- The test suite is self-contained and does not depend on any files from a host app.

### What is Covered by the Specs?

**Model Specs** (`spec/models/spree/payment_method/ipay_spec.rb`):

- Payment completion logic (success, failure, exceptions, nil/malformed responses, already completed, DB errors)
- Void/cancellation logic (success and failure)
- Base URL logic (ensures correct value using Rails URL helpers)
- General payment method behaviors and integration with Spree

**Controller Specs** (`spec/controllers/spree/gateway_callbacks_controller_spec.rb`):

- iPay callback endpoint (`/ipay/confirm`):
  - Valid and invalid callback handling
  - Signature/HMAC verification
  - Payment and order lookup and state transitions
  - Handling of invalid or missing parameters (e.g., order not found, invalid signature)
  - Only existing routes/controllers are tested

**Deprecated/Empty Specs** (`spec/controllers/spree/api/v1/ipay_controller_spec.rb`):

- Deprecated/empty (no actual tests, just a comment for clarity)

**Test Helpers** (`spec/spec_helper.rb`, `spec/rails_helper.rb`):

- Standard RSpec and Rails test configuration for the extension

- Make sure your dummy app is compatible with the Rails and Spree versions required by this extension.

---

## JavaScript Development

This extension includes JavaScript for both frontend and admin interfaces. We use ESLint to maintain code quality.

### Prerequisites

- Node.js (v14 or later)
- npm (v6 or later)

### Setup

1. Install dependencies:

   ```bash
   npm install
   ```

2. Run the linter:

   ```bash
   npx eslint app/assets/javascripts/
   ```

3. (Optional) Add a pre-commit hook using Husky to run the linter before each commit.

### Linting Rules

- Uses ESLint with recommended settings
- Includes jQuery plugin for Spree compatibility
- Custom rules for consistent code style
- Ignores vendor and compiled files

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
