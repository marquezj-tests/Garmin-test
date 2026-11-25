import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Page identifiers, in carousel order. Plain constants rather than an enum
//! so they can be used both as switch labels and as ordinary numbers.
module EssPages {
    const BEAM = 0;
    const POWER = 1;
    const PERMITS = 2;
    const PLANT = 3;
    const MODES = 4;
    const MESSAGE = 5;
    const COUNT = 6;
}

//! The full-screen view. One view draws all six pages and the delegate just
//! moves the page index, which keeps a single web response feeding every page
//! instead of refetching per view push.
class EssPageView extends WatchUi.View {

    //! How often to re-poll while the app is in the foreground. The web
    //! dashboard polls every 5-10 s; 30 s is a deliberate compromise that
    //! keeps the BLE radio and the gateway from being hammered by a watch
    //! the user is only glancing at.
    const REFRESH_SECONDS = 30;

    private var _model as EssModel;
    private var _page as Number = EssPages.BEAM;
    private var _loading as Boolean = false;
    private var _timer as Timer.Timer?;

    public function initialize(model as EssModel) {
        View.initialize();
        _model = model;
    }

    public function onLayout(dc as Dc) as Void {
    }

    public function onShow() as Void {
        refresh();
        var timer = new Timer.Timer();
        timer.start(method(:refresh), REFRESH_SECONDS * 1000, true);
        _timer = timer;
    }

    public function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
    }

    // ---- navigation ------------------------------------------------------

    public function nextPage() as Void {
        _page = (_page + 1) % EssPages.COUNT;
        WatchUi.requestUpdate();
    }

    public function previousPage() as Void {
        _page = (_page + EssPages.COUNT - 1) % EssPages.COUNT;
        WatchUi.requestUpdate();
    }

    // ---- data ------------------------------------------------------------

    //! Kick off a poll. Safe to call from the timer and from the select key.
    public function refresh() as Void {
        if (_loading) {
            return;
        }
        if (!EssApi.isConnected()) {
            _model.setError("No phone\nconnection");
            WatchUi.requestUpdate();
            return;
        }
        _loading = true;
        WatchUi.requestUpdate();
        EssApi.fetchPvs(EssConfig.appPvs(), method(:onPvResponse));
    }

    //! /pvget/ response handler.
    public function onPvResponse(responseCode as Number, data as Dictionary?) as Void {
        _loading = false;
        if (responseCode == 200 && data != null) {
            _model.setData(data as Dictionary);
            // Only ask about gateway health once the data path is known good.
            EssApi.fetchGateway(method(:onGatewayResponse));
        } else {
            _model.setError(EssApi.describeError(responseCode));
        }
        WatchUi.requestUpdate();
    }

    //! Gateway-health response handler.
    public function onGatewayResponse(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode == 200 && data != null) {
            var status = (data as Dictionary).get("gwstatus");
            _model.setGateway(status instanceof String ? status as String : null);
        } else {
            _model.setGateway(null);
        }
        WatchUi.requestUpdate();
    }

    // ---- rendering -------------------------------------------------------

    public function onUpdate(dc as Dc) as Void {
        dc.setAntiAlias(true);
        EssDraw.background(dc);

        if (!_model.hasData()) {
            drawSplash(dc);
            return;
        }

        switch (_page) {
            case EssPages.BEAM:    drawBeam(dc);     break;
            case EssPages.POWER:   drawPower(dc);    break;
            case EssPages.PERMITS: drawPermits(dc);  break;
            case EssPages.PLANT:   drawPlant(dc);    break;
            case EssPages.MODES:   drawModes(dc);    break;
            default:               drawMessage(dc);  break;
        }

        EssDraw.footer(dc, footerText());
    }

    //! Shown until the first response lands.
    private function drawSplash(dc as Dc) as Void {
        var message = _loading ? "Loading..." : EssDraw.str(_model.error());
        if (!_loading && _model.error() == null) {
            message = "Press START\nto load";
        }
        EssDraw.title(dc, "ESS PUBLIC OPI");
        dc.setColor(EssDraw.COLOR_VALUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL, message,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawBeam(dc as Dc) as Void {
        EssDraw.title(dc, "BEAM CURRENT");
        var dest = EssDraw.str(_model.destLabel());
        var fitted = Graphics.fitTextToArea(dest, Graphics.FONT_XTINY,
            (dc.getWidth() * 0.78).toNumber(), dc.getFontHeight(Graphics.FONT_XTINY), true);
        EssDraw.hero(dc, fitted == null ? dest : fitted as String,
            EssDraw.num(_model.beamCurrent(), 1), _model.beamCurrentUnits(),
            EssDraw.severityColor(_model.beamCurrentSeverity()));
        EssDraw.subRows(dc, [
            ["Pulse", EssDraw.num(_model.pulseLength(), 3) + " " + _model.pulseLengthUnits()],
            ["Rate", EssDraw.num(_model.repRate(), 1) + " " + _model.repRateUnits()]
        ] as Array<Array<String> >);
    }

    private function drawPower(dc as Dc) as Void {
        EssDraw.title(dc, "BEAM POWER");
        EssDraw.hero(dc, "average", EssDraw.num(_model.beamPower(), 2), "W",
            EssDraw.COLOR_VALUE);
        EssDraw.subRows(dc, [
            ["Energy", EssDraw.num(_model.beamEnergy(), 1) + " MeV"],
            ["Rate", EssDraw.num(_model.repRate(), 1) + " " + _model.repRateUnits()]
        ] as Array<Array<String> >);
    }

    private function drawPermits(dc as Dc) as Void {
        EssDraw.title(dc, "PERMITS");
        EssDraw.indicators(dc,
            ["Beam permit", "Beam request", "PSS ready", "SHC ready"] as Array<String>,
            [
                _model.indicator(EssConfig.PV_BEAM_PERMIT),
                _model.indicator(EssConfig.PV_BEAM_INHIBIT),
                _model.indicator(EssConfig.PV_PSS_ACTUATORS),
                _model.indicator(EssConfig.PV_SHC_AUTOBEAM)
            ] as Array<Boolean?>);
    }

    private function drawPlant(dc as Dc) as Void {
        EssDraw.title(dc, "PLANT");
        EssDraw.indicators(dc,
            ["4.5K cryo", "2K cryo", "Magnetron", "High voltage"] as Array<String>,
            [
                _model.indicator(EssConfig.PV_CRYO_READY),
                _model.indicator(EssConfig.PV_CRYO_OK),
                _model.indicator(EssConfig.PV_MAGNETRON),
                _model.indicator(EssConfig.PV_HVPS)
            ] as Array<Boolean?>);
    }

    private function drawModes(dc as Dc) as Void {
        EssDraw.title(dc, "MODES");
        EssDraw.rows(dc, [
            ["Beam mode", EssDraw.str(_model.beamModeLabel())],
            ["PSS mode", EssDraw.str(_model.pssModeLabel())],
            ["RF freq", EssDraw.num(_model.rfFrequency(), 1) + " Hz"],
            ["Src freq", EssDraw.num(_model.sourceFrequency(), 1) + " Hz"]
        ] as Array<Array<String> >);
    }

    private function drawMessage(dc as Dc) as Void {
        EssDraw.title(dc, "CONTROL ROOM");
        var text = EssDraw.str(_model.message());
        var maxWidth = (dc.getWidth() * 0.74).toNumber();
        var lines = EssDraw.wrap(dc, text, Graphics.FONT_SMALL, maxWidth);
        var lineHeight = dc.getFontHeight(Graphics.FONT_SMALL);
        var cx = dc.getWidth() / 2;
        var startY = dc.getHeight() / 2 - ((lines.size() - 1) * lineHeight) / 2;

        dc.setColor(EssDraw.COLOR_VALUE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, startY + i * lineHeight, Graphics.FONT_SMALL, lines[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! "3/6 - 12s" plus the gateway state when the gateway reports trouble.
    private function footerText() as String {
        var text = (_page + 1).toString() + "/" + EssPages.COUNT.toString();
        var age = _model.ageSeconds();
        if (age != null) {
            text += "  " + (age as Number).toString() + "s";
        }
        if (_loading) {
            text += "  ...";
        }
        var gateway = _model.gateway();
        if (gateway != null && !(gateway as String).equals("OK")) {
            text += "  GW " + (gateway as String);
        }
        var error = _model.error();
        if (error != null) {
            text += "  !";
        }
        return text;
    }
}
