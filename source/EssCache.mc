import Toybox.Application;
import Toybox.Lang;

//! Storage keys shared between the full-screen app and the glance.
//!
//! Kept in its own (:glance)-annotated module so the glance build can read the
//! cached headline without pulling in EssModel, which is foreground-only.
(:glance)
module EssCache {

    //! Application.Storage key holding the last summary written by the app.
    const KEY_SUMMARY = "ess_summary";

    //! Read back the cached summary, or null if the app has never run.
    function summary() as Dictionary? {
        var stored = Application.Storage.getValue(KEY_SUMMARY);
        if (stored instanceof Dictionary) {
            return stored as Dictionary;
        }
        return null;
    }
}
