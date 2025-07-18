//= require spree/frontend/checkout/payment/ipay

// iPay payment integration for Spree
Spree.ready(($) => {
  "use strict";

  // Initialize iPay payment method
  const initIpay = () => {
    const $ipayMethod = $("#payment_method_spree_ipay");

    if ($ipayMethod.length) {
      // Handle initial state
      if ($ipayMethod.is(":checked")) {
        $(".payment-sources").hide();
        $("#ipay-details").show();
      }

      // Handle payment method change
      $(
        'input[type="radio"][name="order[payments_attributes][][payment_method_id]"]',
      ).on("change", (event) => {
        const $target = $(event.target);
        if ($target.attr("id") === "payment_method_spree_ipay") {
          $(".payment-sources").hide();
          $("#ipay-details").show();
        } else {
          $("#ipay-details").hide();
          $(".payment-sources").show();
        }
      });
    }
  };

  // Initialize on page load and turbolinks page:change
  initIpay();
  $(document).on("page:change", initIpay);
});
