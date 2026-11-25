import Toybox.Lang;

//! Endpoints and EPICS process variable (PV) names behind the ESS
//! "Public Operations Screen" at https://pos.ess.eu/.
//!
//! The web dashboard is a Freeboard instance whose datasources poll a small
//! FastAPI gateway. Two endpoints matter here:
//!
//!   GET /data/api/v2/pvget/<pv>[,<pv>...]  -> live values, one JSON object
//!                                             keyed by PV name
//!   GET /data/-/gwhealth/NSO:Ops:SID       -> {"gwstatus":"OK"|"KO"}
//!
//! Neither endpoint needs authentication. A PV that the gateway has not been
//! asked for recently answers {"value":null,"status":"queued"} on the first
//! request and carries a real value on the next one.
(:glance)
module EssConfig {

    //! Live-value endpoint. PV names are appended comma-separated.
    const PVGET_URL = "https://pos.ess.eu/data/api/v2/pvget/";

    //! Gateway health endpoint.
    const GWHEALTH_URL = "https://pos.ess.eu/data/-/gwhealth/NSO:Ops:SID";

    // ---- Operator message ------------------------------------------------
    //! Message of the day. A char-array PV: arrives as character codes.
    const PV_MSG = "NSO:Ops:Msg";

    // ---- Permits and interlocks (all enum PVs) ---------------------------
    const PV_BEAM_PERMIT   = "FBIS::beam_permit_ok";              // NOK / OK
    const PV_BEAM_INHIBIT  = "TD-M:Ctrl-SCE-1:SwBInhibit-Sel";    // 0 = requested
    const PV_PSS_ACTUATORS = "FEB-010Row:CnPw-U-007:Actuators-On";
    const PV_SHC_AUTOBEAM  = "CrS-SHC::OpMode_AutoBeam";
    const PV_CRYO_READY    = "CrS-CDS:SC-FSM-145:CryoReady";      // 4.5 K
    const PV_CRYO_OK       = "CrS-CDS:SC-FSM-145:CryoOK";         // 2 K
    const PV_MAGNETRON     = "ISrc-CS:ISS-Magtr-01:Mw-S";
    const PV_HVPS          = "ISrc-CS:ISS-HVPS-01:Pwr-R";

    // ---- Modes (enum PVs) ------------------------------------------------
    const PV_BEAM_MODE = "TD-M:Ctrl-SCE-1:BMod-Sel";
    const PV_BEAM_DEST = "TD-M:Ctrl-SCE-1:BDest-Sel";
    const PV_PSS_MODE  = "AccPSS::PSSMode";

    // ---- Frequencies (numeric PVs, Hz) -----------------------------------
    const PV_BEAM_FREQ = "NSO-BProd::BFreqMeas";
    const PV_RF_FREQ   = "TD-M:Ctrl-SCE-1:NepEvtRfStFreqIdeal-I";
    const PV_SRC_FREQ  = "TD-M:Ctrl-SCE-1:NepEvtIonMagStFreqIdeal-I";

    //! Number of beam-destination choices the dashboard knows how to resolve.
    const DEST_COUNT = 8;

    //! Beam-current PV (mA) for each beam-destination index, mirroring the
    //! "Beam Current" widget on the public dashboard.
    function currentPvs() as Array<String> {
        return [
            "ISrc-010:PBI-BCM-001:FlatTopCurrentR",     // 0 Ion source
            "LEBT-010:PBI-FC-001:STAT3-MeanValueR",     // 1 LEBT faraday cup
            "MEBT-010:PBI-FC-001:STAT3-MeanValueR",     // 2 MEBT faraday cup
            "DTL-020:PBI-FC-001:STAT3-MeanValueR",      // 3 DTL2 faraday cup
            "DTL-040:PBI-FC-001:STAT3-MeanValueR",      // 4 DTL4 faraday cup
            "DTL-050:PBI-BCM-001:FlatTopCurrentR",      // 5 DTL5
            "MBL-010LWU:PBI-BCM-001:FlatTopCurrentR",   // 6 Medium beta line
            "DmpL-040Drf:PBI-BCM-001:FlatTopCurrentR"   // 7 Beam dump line
        ];
    }

    //! Pulse-width PV (ms) for each beam-destination index. Index 0 has no
    //! pulse-width source on the dashboard and is reported as zero.
    function pulsePvs() as Array<String> {
        return [
            "",                                         // 0 Ion source
            "ISrc-010:PBI-BCM-001:PulseWidthR",         // 1
            "MEBT-010:PBI-BCM-001:PulseWidthR",         // 2
            "DTL-010:PBI-BCM-001:PulseWidthR",          // 3
            "ISrc-010:PBI-BCM-001:PulseWidthR",         // 4
            "DTL-040:PBI-BCM-001:PulseWidthR",          // 5
            "MBL-010LWU:PBI-BCM-001:PulseWidthR",       // 6
            "HEBT-010LWU:PBI-BCM-001:PulseWidthR"       // 7
        ];
    }

    //! Beam energy in MeV used by the dashboard's *power* calculation.
    function powerEnergies() as Array<Float> {
        return [0.0, 0.075, 3.6, 39.1, 73.8, 89.9, 216.0, 856.0];
    }

    //! Beam energy in MeV as the dashboard *displays* it. Upstream uses
    //! slightly different figures for destinations 6 and 7 than the power
    //! calculation above does; both sets are reproduced verbatim so the watch
    //! agrees with the web page rather than silently "correcting" it.
    function displayEnergies() as Array<Float> {
        return [0.0, 0.075, 3.6, 39.1, 73.8, 89.9, 361.5, 869.0];
    }

    //! Every PV the full-screen app asks for, in one request.
    function appPvs() as Array<String> {
        var pvs = [
            PV_MSG,
            PV_BEAM_PERMIT, PV_BEAM_INHIBIT, PV_PSS_ACTUATORS, PV_SHC_AUTOBEAM,
            PV_CRYO_READY, PV_CRYO_OK, PV_MAGNETRON, PV_HVPS,
            PV_BEAM_MODE, PV_BEAM_DEST, PV_PSS_MODE,
            PV_BEAM_FREQ, PV_RF_FREQ, PV_SRC_FREQ
        ] as Array<String>;
        var currents = currentPvs();
        for (var i = 0; i < currents.size(); i++) {
            pvs.add(currents[i]);
        }
        var pulses = pulsePvs();
        for (var j = 0; j < pulses.size(); j++) {
            var pv = pulses[j];
            if (!pv.equals("") && pvs.indexOf(pv) < 0) {
                pvs.add(pv);
            }
        }
        return pvs;
    }

    //! The much smaller PV set used by the glance, which runs in a 64 KB
    //! memory pool on the FR265 and cannot afford the full ~15 KB response.
    function glancePvs() as Array<String> {
        return [PV_BEAM_DEST, PV_BEAM_PERMIT, PV_BEAM_FREQ] as Array<String>;
    }

    //! Build a /pvget/ URL for a list of PVs.
    function pvGetUrl(pvs as Array<String>) as String {
        var url = PVGET_URL;
        for (var i = 0; i < pvs.size(); i++) {
            if (i > 0) {
                url += ",";
            }
            url += pvs[i];
        }
        return url;
    }
}
