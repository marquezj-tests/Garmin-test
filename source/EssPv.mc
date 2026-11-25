import Toybox.Lang;

//! Decoders for the pvAccess-flavoured JSON that the ESS gateway returns.
//!
//! Every PV in a /pvget/ response is an object of the shape
//!
//!   "NSO-BProd::BFreqMeas": {
//!     "value": 0.3333,
//!     "alarm": { "severity": 0, "status": 0, "message": "" },
//!     "timeStamp": { "secondsPastEpoch": 1795602599, "nanoseconds": ... },
//!     "display": { "units": "Hz", "precision": 3, "description": ... },
//!     ...
//!   }
//!
//! "value" takes three different shapes, and each needs its own decoder:
//!
//!   numeric   0.3333
//!   enum      { "index": 1, "choices": ["NOK", "OK"] }
//!   string    [76, 111, 110, 103]        <- char codes, not a JSON string
//!
//! A PV the gateway has not served recently comes back as
//! { "value": null, "status": "queued", "monitor_wait_seconds": 0.0 }.
(:glance)
module EssPv {

    //! EPICS alarm severities.
    const SEV_NONE = 0;
    const SEV_MINOR = 1;
    const SEV_MAJOR = 2;
    const SEV_INVALID = 3;

    //! Fetch the record for one PV, or null when it is absent or malformed.
    function record(data as Dictionary?, pv as String) as Dictionary? {
        if (data == null) {
            return null;
        }
        var entry = (data as Dictionary).get(pv);
        if (entry instanceof Dictionary) {
            return entry as Dictionary;
        }
        return null;
    }

    //! True when the gateway has accepted the PV but has no value for it yet.
    //! The caller should keep the previous value and try again shortly.
    function isQueued(data as Dictionary?, pv as String) as Boolean {
        var rec = record(data, pv);
        if (rec == null) {
            return false;
        }
        return (rec as Dictionary).get("value") == null
            && (rec as Dictionary).get("status") != null;
    }

    //! Decode a numeric PV to a Float, or null when it is not numeric.
    function number(data as Dictionary?, pv as String) as Float? {
        var rec = record(data, pv);
        if (rec == null) {
            return null;
        }
        var value = (rec as Dictionary).get("value");
        if (value instanceof Float) {
            return value as Float;
        }
        if (value instanceof Double) {
            return (value as Double).toFloat();
        }
        if (value instanceof Number) {
            return (value as Number).toFloat();
        }
        if (value instanceof Long) {
            return (value as Long).toFloat();
        }
        return null;
    }

    //! Decode the selected index of an enum PV.
    function enumIndex(data as Dictionary?, pv as String) as Number? {
        var rec = record(data, pv);
        if (rec == null) {
            return null;
        }
        var value = (rec as Dictionary).get("value");
        if (!(value instanceof Dictionary)) {
            return null;
        }
        var index = (value as Dictionary).get("index");
        if (index instanceof Number) {
            return index as Number;
        }
        return null;
    }

    //! Decode the selected label of an enum PV, e.g. "BeamDump" or "OK".
    function enumLabel(data as Dictionary?, pv as String) as String? {
        var rec = record(data, pv);
        if (rec == null) {
            return null;
        }
        var value = (rec as Dictionary).get("value");
        if (!(value instanceof Dictionary)) {
            return null;
        }
        var index = (value as Dictionary).get("index");
        var choices = (value as Dictionary).get("choices");
        if (!(index instanceof Number) || !(choices instanceof Array)) {
            return null;
        }
        var list = choices as Array;
        var i = index as Number;
        if (i < 0 || i >= list.size()) {
            return null;
        }
        var label = list[i];
        if (label instanceof String) {
            return label as String;
        }
        return null;
    }

    //! Decode a string PV. EPICS char arrays arrive as character codes, so
    //! [76, 111, 110, 103] has to be rebuilt into "Long".
    function text(data as Dictionary?, pv as String) as String? {
        var rec = record(data, pv);
        if (rec == null) {
            return null;
        }
        var value = (rec as Dictionary).get("value");
        if (value instanceof String) {
            return value as String;
        }
        if (!(value instanceof Array)) {
            return null;
        }
        var codes = value as Array;
        var out = "";
        for (var i = 0; i < codes.size(); i++) {
            var code = codes[i];
            if (!(code instanceof Number)) {
                continue;
            }
            var ch = code as Number;
            if (ch <= 0) {
                break;          // NUL terminates the EPICS string
            }
            out += ch.toChar().toString();
        }
        return out;
    }

    //! Engineering units from the PV's display metadata ("Hz", "mA", "ms").
    function units(data as Dictionary?, pv as String) as String {
        var rec = record(data, pv);
        if (rec == null) {
            return "";
        }
        var display = (rec as Dictionary).get("display");
        if (!(display instanceof Dictionary)) {
            return "";
        }
        var value = (display as Dictionary).get("units");
        if (value instanceof String) {
            return value as String;
        }
        return "";
    }

    //! Alarm severity, defaulting to SEV_NONE when the PV carries no alarm
    //! block and SEV_INVALID when the PV is missing altogether.
    function severity(data as Dictionary?, pv as String) as Number {
        var rec = record(data, pv);
        if (rec == null) {
            return SEV_INVALID;
        }
        var alarm = (rec as Dictionary).get("alarm");
        if (!(alarm instanceof Dictionary)) {
            return SEV_NONE;
        }
        var value = (alarm as Dictionary).get("severity");
        if (value instanceof Number) {
            return value as Number;
        }
        return SEV_NONE;
    }
}
