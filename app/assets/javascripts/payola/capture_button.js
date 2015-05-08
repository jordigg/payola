var PayolaCapture = {
    initialize: function() {
        $(document).on('click', '.payola-capture-button', function(e) {
            e.preventDefault();
            PayolaCapture.handleCaptureButtonClick($(this));
        });
    },

    handleCaptureButtonClick: function(button) {
        var form = button.parent('form');
        var options = form.data();

        $(".payola-capture-button").prop("disabled", true);
        $(".payola-capture-button-text").hide();
        $(".payola-capture-button-spinner").show();
        $.ajax({
            type: "GET",
            url: options.base_path + "/capture/" + options.sale_guid,
            data: form.serialize(),
            success: function(data) { PayolaCapture.poll(data.guid, 60, options); },
            error: function(data) { PayolaCapture.showError(data.responseJSON.error, options); }
        });
    },

    showError: function(error, options) {
        var error_div = $("#" + options.error_div_id);
        error_div.html(error);
        error_div.show();
        $(".payola-capture-button").prop("disabled", false);
        $(".payola-capture-button-spinner").hide();
        $(".payola-capture-button-text").show();
    },

    poll: function(guid, num_retries_left, options) {
        if (num_retries_left === 0) {
            PayolaCapture.showError("This seems to be taking too long. Please contact support and give them transaction ID: " + guid, options);
            return;
        }

        var handler = function(data) {
            if (data.status === "finished") {
                window.location = options.base_path + "/confirm/" + guid;
            } else if (data.status === "errored") {
                PayolaCapture.showError(data.error, options);
            } else {
                setTimeout(function() { PayolaCapture.poll(guid, num_retries_left - 1, options); }, 500);
            }
        };

        $.ajax({
            type: "GET",
            url: options.base_path + "/status/" + guid,
            success: handler,
            error: handler
        });
    }
};
$(function() { PayolaCapture.initialize(); });
