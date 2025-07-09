// Backend iPay integration for Spree
Spree.ready(function ($) {
  "use strict";

  // Add any backend-specific JavaScript here
  // For example, you might want to add admin panel functionality
  // or payment method configuration options

  // Toggle iPay settings based on payment method selection
  $(document).on("change", ".payment-method-type-select", function () {
    var isIpay = $(this).val() === "Spree::PaymentMethod::Ipay";
    $(".ipay-settings").toggle(isIpay);
  });

  // Initialize on page load
  $(".payment-method-type-select").trigger("change");
});
