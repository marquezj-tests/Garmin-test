import Toybox.Graphics;
import Toybox.Lang;

//! Drawing helpers shared by the full-screen pages and the glance.
//!
//! Everything is expressed as a fraction of the device context, so the same
//! code lays out correctly on the 416x416 Forerunner 265 and the 360x360
//! Forerunner 265s. Horizontal margins are kept at 10% of the width so text
//! never runs into the bezel on a round display.
(:glance)
module EssDraw {

    // AMOLED-friendly palette: a black field costs almost no power on this
    // panel, and the accent colours stay readable at 60% display brightness.
    const COLOR_BG     = Graphics.COLOR_BLACK;
    const COLOR_LABEL  = 0x888888;
    const COLOR_VALUE  = Graphics.COLOR_WHITE;
    const COLOR_ACCENT = 0xFFB000;
    const COLOR_GOOD   = 0x00C853;
    const COLOR_BAD    = 0xE53935;
    const COLOR_UNKNOWN = 0x555555;

    //! Placeholder for a value that has not arrived yet.
    const NO_VALUE = "--";

    //! Format a float with a fixed number of decimals, or NO_VALUE if null.
    function num(value as Float?, decimals as Number) as String {
        if (value == null) {
            return NO_VALUE;
        }
        return (value as Float).format("%." + decimals.toString() + "f");
    }

    //! Return the string, or NO_VALUE if it is null or empty.
    function str(value as String?) as String {
        if (value == null || (value as String).equals("")) {
            return NO_VALUE;
        }
        return value as String;
    }

    //! Colour for a tri-state indicator.
    function stateColor(state as Boolean?) as Number {
        if (state == null) {
            return COLOR_UNKNOWN;
        }
        return (state as Boolean) ? COLOR_GOOD : COLOR_BAD;
    }

    //! Word for a tri-state indicator.
    function stateWord(state as Boolean?) as String {
        if (state == null) {
            return NO_VALUE;
        }
        return (state as Boolean) ? "OK" : "NOK";
    }

    //! Colour for an EPICS alarm severity: white when clear, amber on a minor
    //! alarm, red on a major or invalid one.
    function severityColor(severity as Number) as Number {
        if (severity == EssPv.SEV_NONE) {
            return COLOR_VALUE;
        }
        if (severity == EssPv.SEV_MINOR) {
            return COLOR_ACCENT;
        }
        return COLOR_BAD;
    }

    //! Clear the screen to the background colour.
    function background(dc as Dc) as Void {
        dc.setColor(COLOR_VALUE, COLOR_BG);
        dc.clear();
    }

    //! Dimmed page title across the top of a round screen.
    function title(dc as Dc, text as String) as Void {
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, (dc.getHeight() * 0.13).toNumber(),
            Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Dimmed footer: page position on the left, data age on the right.
    function footer(dc as Dc, text as String) as Void {
        dc.setColor(COLOR_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, (dc.getHeight() * 0.86).toNumber(),
            Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! A single large reading: caption, big number, units. valueColor lets the
    //! caller reflect the PV's alarm severity in the headline figure.
    function hero(dc as Dc, caption as String, value as String, units as String, valueColor as Number) as Void {
        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();

        dc.setColor(COLOR_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.28).toNumber(), Graphics.FONT_XTINY, caption,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.44).toNumber(), Graphics.FONT_NUMBER_MEDIUM, value,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (!units.equals("")) {
            dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.59).toNumber(), Graphics.FONT_TINY, units,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Two secondary label/value rows below a hero reading.
    function subRows(dc as Dc, rows as Array<Array<String> >) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var margin = (w * 0.14).toNumber();
        var first = 0.68;
        var step = 0.095;

        for (var i = 0; i < rows.size(); i++) {
            var y = (h * (first + step * i)).toNumber();
            dc.setColor(COLOR_LABEL, Graphics.COLOR_TRANSPARENT);
            dc.drawText(margin, y, Graphics.FONT_XTINY, rows[i][0],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_VALUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - margin, y, Graphics.FONT_XTINY, rows[i][1],
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Four evenly spaced label/value rows filling the content band.
    function rows(dc as Dc, items as Array<Array<String> >) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var margin = (w * 0.10).toNumber();
        var count = items.size();
        if (count == 0) {
            return;
        }
        var top = 0.30;
        var span = 0.42;
        var step = count > 1 ? span / (count - 1) : 0.0;

        for (var i = 0; i < count; i++) {
            var y = (h * (top + step * i)).toNumber();
            dc.setColor(COLOR_LABEL, Graphics.COLOR_TRANSPARENT);
            dc.drawText(margin, y - (h * 0.045).toNumber(), Graphics.FONT_XTINY, items[i][0],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(COLOR_VALUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - margin, y - (h * 0.045).toNumber(), Graphics.FONT_TINY, items[i][1],
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Rows of coloured status dots with a label and a state word, mirroring
    //! the red/amber/green indicators on the web dashboard.
    //!
    //! Labels and states are passed as two parallel arrays rather than one
    //! array of pairs: a pair would have to be typed Array<Object or Null> to
    //! hold a String next to a nullable Boolean, which the type checker
    //! cannot usefully verify.
    function indicators(dc as Dc, labels as Array<String>, states as Array<Boolean?>) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var margin = (w * 0.12).toNumber();
        var count = labels.size();
        if (count == 0) {
            return;
        }
        var top = 0.28;
        var span = 0.44;
        var step = count > 1 ? span / (count - 1) : 0.0;
        var radius = (w * 0.022).toNumber();

        for (var i = 0; i < count; i++) {
            var y = (h * (top + step * i)).toNumber();
            var state = i < states.size() ? states[i] : null;

            dc.setColor(stateColor(state), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(margin + radius, y, radius);

            dc.setColor(COLOR_VALUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(margin + radius * 3, y, Graphics.FONT_XTINY, labels[i],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(stateColor(state), Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - margin, y, Graphics.FONT_XTINY, stateWord(state),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Greedy word wrap for the operator message. Lines wider than the given
    //! width are broken on spaces; single long words are left to overflow
    //! rather than being chopped mid-word.
    function wrap(dc as Dc, text as String, font as Graphics.FontType, maxWidth as Number) as Array<String> {
        var words = splitWords(text);
        var lines = [] as Array<String>;
        var line = "";
        for (var i = 0; i < words.size(); i++) {
            var candidate = line.equals("") ? words[i] : line + " " + words[i];
            if (dc.getTextWidthInPixels(candidate, font) <= maxWidth || line.equals("")) {
                line = candidate;
            } else {
                lines.add(line);
                line = words[i];
            }
        }
        if (!line.equals("")) {
            lines.add(line);
        }
        return lines;
    }

    //! Split on single spaces. Monkey C has no String.split, so this walks
    //! the characters once.
    function splitWords(text as String) as Array<String> {
        var words = [] as Array<String>;
        var chars = text.toCharArray();
        var current = "";
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i];
            if (ch == ' ') {
                if (!current.equals("")) {
                    words.add(current);
                    current = "";
                }
            } else {
                current += ch.toString();
            }
        }
        if (!current.equals("")) {
            words.add(current);
        }
        return words;
    }
}
