// iPay payment processor
Spree.routes = Spree.routes || {};
Spree.routes.ipay_payments = Spree.pathFor("api/ipay/payments");

Spree.ready(function ($) {
  "use strict";

  // Show flash message
  function showFlash(type, message) {
    const flashDiv = $(`<div class="alert alert-${type}">${message}</div>`);
    $(".progress-steps").before(flashDiv);
    flashDiv.slideDown();

    // Auto-hide after 5 seconds
    setTimeout(() => {
      flashDiv.slideUp(400, function () {
        $(this).remove();
      });
    }, 5000);
  }

  // Handle iPay payment form submission
  $(".checkout_form_payment").on("submit", function (e) {
    const $form = $(this);
    const $submitButton = $form.find(
      'input[type="submit"], button[type="submit"]',
    );

    if ($("#payment_method_spree_ipay").is(":checked")) {
      e.preventDefault();

      // Show loading state
      const originalText = $submitButton.val() || $submitButton.text();
      $submitButton
        .prop("disabled", true)
        .val(Spree.translations.processing || "Processing...");

      // Clear previous errors
      $(".form-error").remove();
      $(".field_with_errors").removeClass("field_with_errors");

      // Get form data
      const formData = $form.serialize();

      // Submit the form via AJAX
      $.ajax({
        url: Spree.pathFor("checkout/update/payment"),
        method: "POST",
        data: formData,
        dataType: "json",
        headers: {
          "X-CSRF-Token": $('meta[name="csrf-token"]').attr("content"),
        },
      })
        .done(function (response) {
          if (response.redirect) {
            // Redirect to payment gateway or next step
            window.location.href = response.redirect;
          } else if (response.next_step_required) {
            // Handle next step in checkout
            window.location.reload();
          } else {
            // Handle unexpected response
            showFlash(
              "error",
              Spree.translables.payment_processing_failed ||
                "Payment processing failed",
            );
            $submitButton.prop("disabled", false).val(originalText);
          }
        })
        .fail(function (xhr) {
          let errorMessage =
            Spree.translables.payment_processing_failed ||
            "Payment processing failed";

          // Try to extract error message from response
          try {
            const response = JSON.parse(xhr.responseText);
            errorMessage = response.error || response.message || errorMessage;

            // Handle form validation errors
            if (response.errors) {
              $.each(response.errors, function (field, messages) {
                const $field = $(`[name*="${field}"]`).first();
                if ($field.length) {
                  const $errorDiv = $(
                    `<div class="form-error">${messages.join(", ")}</div>`,
                  );
                  $field
                    .after($errorDiv)
                    .closest(".form-group")
                    .addClass("field_with_errors");
                }
              });
            }
          } catch (e) {
            console.error("Error parsing error response:", e);
          }

          showFlash("error", errorMessage);
          $submitButton.prop("disabled", false).val(originalText);
        });
    }
  });
});
