import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

//! Thin wrapper around Communications.makeWebRequest for the ESS gateway.
//!
//! On a Forerunner 265 the request leaves the watch either over Wi-Fi or, far
//! more often, over BLE through the Garmin Connect app on the phone. Both
//! paths are asynchronous and both can fail in ways an HTTP status code
//! cannot express, so the error mapping below turns the BLE_* / NETWORK_*
//! response codes into something worth putting on a 416 px screen.
(:glance)
module EssApi {

    //! Issue a /pvget/ request for the given PVs.
    //! @param pvs PV names to fetch
    //! @param callback method(responseCode as Number, data as Dictionary?)
    function fetchPvs(pvs as Array<String>, callback as Method(responseCode as Number, data as Dictionary?) as Void) as Void {
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        // The PV list goes in the path, not in the query string: passing it as
        // a `parameters` dictionary would percent-encode the commas and
        // colons the gateway expects to see literally.
        Communications.makeWebRequest(EssConfig.pvGetUrl(pvs), null, options, callback);
    }

    //! Issue a gateway-health request. Returns {"gwstatus":"OK"|"KO"}.
    function fetchGateway(callback as Method(responseCode as Number, data as Dictionary?) as Void) as Void {
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(EssConfig.GWHEALTH_URL, null, options, callback);
    }

    //! Turn a response code into a short message that fits on the watch.
    function describeError(responseCode as Number) as String {
        if (responseCode == Communications.BLE_CONNECTION_UNAVAILABLE) {
            return "No phone\nconnection";
        }
        if (responseCode == Communications.BLE_HOST_TIMEOUT
            || responseCode == Communications.BLE_SERVER_TIMEOUT
            || responseCode == Communications.NETWORK_REQUEST_TIMED_OUT) {
            return "Request\ntimed out";
        }
        if (responseCode == Communications.BLE_QUEUE_FULL) {
            return "Radio busy,\nretrying";
        }
        if (responseCode == Communications.BLE_REQUEST_TOO_LARGE) {
            return "Request\ntoo large";
        }
        if (responseCode == Communications.NETWORK_RESPONSE_TOO_LARGE
            || responseCode == Communications.NETWORK_RESPONSE_OUT_OF_MEMORY) {
            return "Response\ntoo large";
        }
        if (responseCode == Communications.INVALID_HTTP_BODY_IN_NETWORK_RESPONSE) {
            return "Bad response\nbody";
        }
        if (responseCode == Communications.BLE_REQUEST_CANCELLED
            || responseCode == Communications.REQUEST_CANCELLED) {
            return "Request\ncancelled";
        }
        if (responseCode == 404) {
            return "PV not found\n(404)";
        }
        if (responseCode >= 500) {
            return "Gateway error\n(" + responseCode.toString() + ")";
        }
        if (responseCode < 0) {
            return "Comms error\n(" + responseCode.toString() + ")";
        }
        return "HTTP " + responseCode.toString();
    }

    //! True when the watch currently has any route to the internet. Checked
    //! before a request so the UI can say "no connection" immediately instead
    //! of waiting for the radio to time out.
    function isConnected() as Boolean {
        var settings = System.getDeviceSettings();
        if (settings.connectionAvailable) {
            return true;
        }
        return settings.phoneConnected;
    }
}
