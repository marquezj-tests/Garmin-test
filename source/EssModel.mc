import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;

//! One decoded snapshot of the ESS public operations screen, plus the derived
//! quantities the dashboard computes in JavaScript on the web page.
class EssModel {

    //! Raw /pvget/ response, or null before the first successful fetch.
    private var _data as Dictionary?;
    //! Human-readable failure reason for the most recent attempt.
    private var _error as String?;
    //! Device clock (seconds past epoch) at which _data was received.
    private var _fetchedAt as Number?;
    //! Gateway self-reported health, "OK" / "KO" / null if unknown.
    private var _gateway as String?;

    public function initialize() {
        _data = null;
        _error = null;
        _fetchedAt = null;
        _gateway = null;
    }

    // ---- ingest ----------------------------------------------------------

    //! Accept a successful /pvget/ response.
    public function setData(data as Dictionary) as Void {
        _data = data;
        _error = null;
        _fetchedAt = Time.now().value();
        cache();
    }

    //! Record a failed attempt. Any previously fetched values are kept so the
    //! user still sees the last known state alongside the error.
    public function setError(message as String) as Void {
        _error = message;
    }

    public function setGateway(status as String?) as Void {
        _gateway = status;
    }

    public function hasData() as Boolean {
        return _data != null;
    }

    public function error() as String? {
        return _error;
    }

    public function gateway() as String? {
        return _gateway;
    }

    //! Seconds since this snapshot was fetched, or null if never fetched.
    public function ageSeconds() as Number? {
        if (_fetchedAt == null) {
            return null;
        }
        var age = Time.now().value() - (_fetchedAt as Number);
        return age < 0 ? 0 : age;
    }

    // ---- enum / mode accessors -------------------------------------------

    //! Beam-destination index, which selects which beam-current and
    //! pulse-width PV is the relevant one.
    public function destIndex() as Number? {
        return EssPv.enumIndex(_data, EssConfig.PV_BEAM_DEST);
    }

    public function destLabel() as String? {
        return EssPv.enumLabel(_data, EssConfig.PV_BEAM_DEST);
    }

    public function beamModeLabel() as String? {
        return EssPv.enumLabel(_data, EssConfig.PV_BEAM_MODE);
    }

    public function pssModeLabel() as String? {
        return EssPv.enumLabel(_data, EssConfig.PV_PSS_MODE);
    }

    public function message() as String? {
        return EssPv.text(_data, EssConfig.PV_MSG);
    }

    // ---- indicators ------------------------------------------------------

    //! Tri-state indicator: true = good, false = not good, null = unknown.
    //! Mirrors the dashboard's RAG widgets, which map enum index 1 to green
    //! for every signal except the beam-request inhibit, where 0 is green.
    public function indicator(pv as String) as Boolean? {
        var index = EssPv.enumIndex(_data, pv);
        if (index == null) {
            return null;
        }
        if (pv.equals(EssConfig.PV_BEAM_INHIBIT)) {
            return index == 0;
        }
        return index == 1;
    }

    //! Alarm severity for a PV, for colouring values that are in alarm.
    public function severity(pv as String) as Number {
        return EssPv.severity(_data, pv);
    }

    //! Alarm severity of whichever beam-current PV the active destination
    //! selects, so the headline reading can be coloured when the control
    //! system flags it.
    public function beamCurrentSeverity() as Number {
        var dest = destIndex();
        if (dest == null) {
            return EssPv.SEV_INVALID;
        }
        var pvs = EssConfig.currentPvs();
        var i = dest as Number;
        if (i < 0 || i >= pvs.size()) {
            return EssPv.SEV_INVALID;
        }
        return EssPv.severity(_data, pvs[i]);
    }

    // ---- numeric accessors -----------------------------------------------

    public function repRate() as Float? {
        return EssPv.number(_data, EssConfig.PV_BEAM_FREQ);
    }

    //! Engineering units straight from the PV metadata, so the watch labels
    //! match whatever the control system declares rather than hard-coding
    //! them. Falls back to the dashboard's own label when absent.
    public function repRateUnits() as String {
        return unitsOr(EssConfig.PV_BEAM_FREQ, "Hz");
    }

    public function beamCurrentUnits() as String {
        var dest = destIndex();
        if (dest == null) {
            return "mA";
        }
        var pvs = EssConfig.currentPvs();
        var i = dest as Number;
        if (i < 0 || i >= pvs.size()) {
            return "mA";
        }
        return unitsOr(pvs[i], "mA");
    }

    public function pulseLengthUnits() as String {
        var dest = destIndex();
        if (dest == null) {
            return "ms";
        }
        var pvs = EssConfig.pulsePvs();
        var i = dest as Number;
        if (i < 0 || i >= pvs.size() || pvs[i].equals("")) {
            return "ms";
        }
        return unitsOr(pvs[i], "ms");
    }

    private function unitsOr(pv as String, fallback as String) as String {
        var units = EssPv.units(_data, pv);
        return units.equals("") ? fallback : units;
    }

    public function rfFrequency() as Float? {
        return EssPv.number(_data, EssConfig.PV_RF_FREQ);
    }

    public function sourceFrequency() as Float? {
        return EssPv.number(_data, EssConfig.PV_SRC_FREQ);
    }

    //! Beam current in mA for the active destination, clamped at zero exactly
    //! as the dashboard does (the faraday-cup readings drift slightly
    //! negative when there is no beam).
    public function beamCurrent() as Float? {
        var dest = destIndex();
        if (dest == null) {
            return null;
        }
        var pvs = EssConfig.currentPvs();
        var i = dest as Number;
        if (i < 0 || i >= pvs.size()) {
            return null;
        }
        var value = EssPv.number(_data, pvs[i]);
        if (value == null) {
            return null;
        }
        return clampLow(value as Float);
    }

    //! Pulse length in ms for the active destination. Destination 0 (the ion
    //! source) has no pulse-width source on the dashboard and reports zero.
    public function pulseLength() as Float? {
        var dest = destIndex();
        if (dest == null) {
            return null;
        }
        var pvs = EssConfig.pulsePvs();
        var i = dest as Number;
        if (i < 0 || i >= pvs.size()) {
            return null;
        }
        var pv = pvs[i];
        if (pv.equals("")) {
            return 0.0;
        }
        var value = EssPv.number(_data, pv);
        if (value == null) {
            return null;
        }
        return clampLow(value as Float);
    }

    //! Beam energy in MeV as the dashboard displays it.
    public function beamEnergy() as Float? {
        var dest = destIndex();
        if (dest == null) {
            return null;
        }
        var energies = EssConfig.displayEnergies();
        var i = dest as Number;
        if (i < 0 || i >= energies.size()) {
            return null;
        }
        return energies[i];
    }

    //! Average beam power in watts.
    //!
    //!   P[W] = E[MeV] * I[mA] * t[ms] * f[Hz]
    //!
    //! because MeV * mA = kW instantaneous and ms * Hz is the duty factor in
    //! units of 1e-3. Negative results are clamped to zero, as upstream.
    public function beamPower() as Float? {
        var dest = destIndex();
        var current = beamCurrent();
        var pulse = pulseLength();
        var rate = repRate();
        if (dest == null || current == null || pulse == null || rate == null) {
            return null;
        }
        var energies = EssConfig.powerEnergies();
        var i = dest as Number;
        if (i < 0 || i >= energies.size()) {
            return null;
        }
        var power = energies[i] * (current as Float) * (pulse as Float) * (rate as Float);
        return clampLow(power);
    }

    // ---- glance cache ----------------------------------------------------

    //! Persist the handful of fields the glance shows. Writing from the full
    //! app means the glance has something to draw immediately, even before
    //! its own (much smaller) request comes back.
    private function cache() as Void {
        var summary = {
            "dest" => destLabel(),
            "permit" => indicator(EssConfig.PV_BEAM_PERMIT),
            "rate" => repRate(),
            "at" => _fetchedAt
        };
        Application.Storage.setValue(EssCache.KEY_SUMMARY, summary as Application.Storage.ValueType);
    }

    private function clampLow(value as Float) as Float {
        return value < 0.0 ? 0.0 : value;
    }
}
