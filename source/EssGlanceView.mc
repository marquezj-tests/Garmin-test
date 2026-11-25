import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! The glance tile.
//!
//! A glance runs in a 64 KB memory pool on the Forerunner 265, so it must not
//! touch EssModel or ask for the full 29-PV response (~15 KB of JSON, several
//! times that once parsed). Instead it:
//!
//!   1. draws the summary the full app cached in Application.Storage, so
//!      something useful appears instantly, and
//!   2. fires its own three-PV request (~1.2 KB) to freshen the headline.
//!
//! The FR265 is a music-capable wearable, which puts it in the "live UI
//! update" glance class: it stays resident and requestUpdate() works.
(:glance)
class EssGlanceView extends WatchUi.GlanceView {

    private var _dest as String?;
    private var _permit as Boolean?;
    private var _requested as Boolean = false;

    public function initialize() {
        GlanceView.initialize();
    }

    public function onLayout(dc as Dc) as Void {
        loadCache();
    }

    public function onShow() as Void {
        if (!_requested && EssApi.isConnected()) {
            _requested = true;
            EssApi.fetchPvs(EssConfig.glancePvs(), method(:onResponse));
        }
    }

    //! Read the cached headline written by the full app.
    private function loadCache() as Void {
        var summary = EssCache.summary();
        if (summary == null) {
            return;
        }
        var dest = (summary as Dictionary).get("dest");
        if (dest instanceof String) {
            _dest = dest as String;
        }
        var permit = (summary as Dictionary).get("permit");
        if (permit instanceof Boolean) {
            _permit = permit as Boolean;
        }
    }

    public function onResponse(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode == 200 && data != null) {
            var dest = EssPv.enumLabel(data, EssConfig.PV_BEAM_DEST);
            if (dest != null) {
                _dest = dest;
            }
            var permit = EssPv.enumIndex(data, EssConfig.PV_BEAM_PERMIT);
            if (permit != null) {
                _permit = ((permit as Number) == 1);
            }
        }
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setAntiAlias(true);

        var h = dc.getHeight();
        var radius = (h * 0.12).toNumber();
        var dotX = radius + 2;
        var midY = h / 2;

        dc.setColor(EssDraw.stateColor(_permit), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dotX, midY, radius);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dotX + radius * 2, midY, Graphics.FONT_GLANCE,
            "ESS " + EssDraw.str(_dest),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
