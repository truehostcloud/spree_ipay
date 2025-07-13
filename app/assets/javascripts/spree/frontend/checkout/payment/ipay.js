// iPay payment processor
Spree.routes = Spree.routes || {};
Spree.routes.ipay_status = Spree.pathFor("api/v1/ipay/status");
Spree.routes.checkout_update = Spree.pathFor("checkout/update/payment");

Spree.ready(($) => {
  "use strict";

  // Show flash message
  const showFlash = (type, message) => {
    const flashDiv = $(`<div class="alert alert-${type}">${message}</div>`);
    $(".progress-steps").before(flashDiv);
    flashDiv.slideDown();
    setTimeout(() => flashDiv.slideUp(400, () => flashDiv.remove()), 5000);
  };

  // Format currency
  const formatCurrency = (amount, currency) => {
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: currency || "KES",
      minimumFractionDigits: 2,
    }).format(amount);
  };

  // Function to check payment status
  function checkPaymentStatus(orderNumber, maxAttempts = 10, attempt = 1) {
    if (attempt > maxAttempts) {
      showFlash(
        "warning",
        "Payment status check timed out. Please check your order status later.",
      );
      return;
    }

    $.ajax({
      url: Spree.routes.ipay_status,
      method: "GET",
      data: { order_id: orderNumber },
      dataType: "json",
      headers: {
        "X-CSRF-Token": $('meta[name="csrf-token"]').attr("content"),
        Accept: "application/json",
      },
    })
      .done(function (response) {
        if (response.payment && response.payment.state === "completed") {
          // Payment completed, redirect to order confirmation
          window.location.href = Spree.pathFor(`orders/${orderNumber}`);
        } else if (
          response.payment &&
          ["failed", "void", "invalid"].includes(response.payment.state)
        ) {
          // Payment failed
          showFlash(
            "error",
            `Payment ${response.payment.state}. Please try again.`,
          );
          window.location.href = Spree.pathFor("checkout/payment");
        } else {
          // Check again after delay
          setTimeout(() => {
            checkPaymentStatus(orderNumber, maxAttempts, attempt + 1);
          }, 2000);
        }
      })
      .fail(function (xhr) {
        console.error("Error checking payment status:", xhr);
        // Continue checking on failure
        setTimeout(() => {
          checkPaymentStatus(orderNumber, maxAttempts, attempt + 1);
        }, 2000);
      });
  }

  // Handle iPay payment form submission
  $(".checkout_form_payment").on("submit", function (e) {
    const $form = $(this);
    const $submitButton = $form.find(
      'input[type="submit"], button[type="submit"]',
    );
    const $paymentMethod = $("#payment_method_spree_ipay");
    const originalText = $submitButton.val() || $submitButton.text();

    // Only handle iPay payment method
    if (!$paymentMethod.is(":checked")) {
      return true; // Let the form submit normally
    }

    e.preventDefault();

    // Update button state and show loading
    $submitButton
      .prop("disabled", true)
      .val(Spree.translations.processing || "Processing...");
      
    // Add loading indicator
    const $loading = $(
      '<div class="ipay-loading text-center py-4"><div class="spinner-border text-primary" role="status"><span class="visually-hidden">Loading...</span></div><p class="mt-2">Processing payment...</p></div>'
    );
    $form.find(".ipay-loading").remove();
    $form.prepend($loading);

    // Clear previous errors and messages
    $(".form-error, .alert").remove();
    $(".field_with_errors").removeClass("field_with_errors");

    // Get form data
    const formData = $form.serialize();

    // Show loading indicator
    const $loadingIndicator = $(
      '<div class="text-center py-4"><div class="spinner-border text-primary" role="status"><span class="visually-hidden">Loading...</span></div><p class="mt-2">Processing your payment...</p></div>',
    );
    $("#payment-method-fields").append($loadingIndicator);

    // Submit the form via AJAX with JSON support
    $.ajax({
      url: Spree.routes.checkout_update,
      method: "POST",
      data: formData,
      dataType: "json",
      headers: {
        "X-CSRF-Token": $('meta[name="csrf-token"]').attr("content"),
        "X-Requested-With": "XMLHttpRequest",
        Accept: "application/json"
      }
    })
      .done((response) => {
        // Handle successful response
        if (response.redirect_url) {
          // If we get a redirect URL, navigate to it
          window.location.href = response.redirect_url;
        } else if (response.status === "success") {
          if (response.next_step === "confirm") {
            // If we're moving to confirm, reload the page to show the iPay form
            window.location.href = Spree.pathFor("checkout/confirm");
          } else if (response.next_step === "complete") {
            // If order is complete, redirect to order confirmation
            window.location.href = 
              response.order?.complete_url || 
              Spree.pathFor(`orders/${response.order?.number}`);
          } else if (response.next_step_url) {
            // For other successful steps with explicit URL
            window.location.href = response.next_step_url;
          } else if (response.next_step) {
            // For other steps, construct the URL
            window.location.href = Spree.pathFor(`checkout/${response.next_step}`);
          } else {
            // Fallback to page reload if no specific action
            window.location.reload();
          }
        } else {
          // Handle error response
          const errorMessage = response.message || "Payment processing failed";
          const errors = [];
          
          // Show form validation errors if any
          if (response.errors) {
            Object.entries(response.errors).forEach(([field, messages]) => {
              const $field = $(`[name*="[${field}]"]`).first();
              if ($field.length) {
                const errorText = Array.isArray(messages) ? messages.join(", ") : messages;
                const $errorDiv = $(`<div class="form-error text-danger small">${errorText}</div>`);
                $field.after($errorDiv);
                $field.closest(".form-group").addClass("has-error");
                errors.push(errorText);
              }
            });
          }
          
          showFlash("error", [errorMessage, ...errors].filter(Boolean).join(" "));
          $submitButton.prop("disabled", false).val(originalText);
        }
      })
      .fail((xhr) => {
        let errorMessage = "Payment processing failed. Please try again.";
        let errors = [];

        try {
          const response = xhr.responseJSON || {};
          if (response.message) {
            errorMessage = response.message;
          }
          if (response.errors) {
            errors = Object.values(response.errors).flat();
          }
        } catch (e) {
          console.error("Error parsing error response:", e);
        }

        showFlash("error", [errorMessage, ...errors].filter(Boolean).join(" "));
        $submitButton.prop("disabled", false).val(originalText);
      })
      .always(() => {
        $loadingIndicator.remove();
        $loading.remove();
      });
  });

  // Initialize payment method visibility
  const updatePaymentMethodVisibility = () => {
    $('.payment-methods input[type="radio"]').each(function () {
      const $method = $(this);
      const $fieldset = $method.closest(".payment-method");
      if ($method.is(":checked")) {
        $fieldset.addClass("selected");
      } else {
        $fieldset.removeClass("selected");
      }
    });
  };

  // Handle payment method selection
  $(document).on(
    "change",
    '.payment-methods input[type="radio"]',
    updatePaymentMethodVisibility,
  );

  // Initialize on page load
  updatePaymentMethodVisibility();

  // Check for pending payments on page load
  const $pendingPayment = $(".payment-pending");
  if ($pendingPayment.length) {
    const orderNumber = $pendingPayment.data("order-number");
    if (orderNumber) {
      showFlash("info", "Checking payment status...");
      checkPaymentStatus(orderNumber);
    }
  }
});
