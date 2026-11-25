import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! ESS Public OPI - a Connect IQ device app that mirrors the public operations
//! screen of the European Spallation Source (https://pos.ess.eu/) on a Garmin
//! Forerunner 265.
//!
//! The class carries (:glance) because the application object has to exist in
//! glance scope for the system to call getGlanceView() there. getInitialView()
//! and everything it reaches (EssModel, EssPageView, EssPageDelegate) are
//! deliberately left out of that scope, so the scope check on getInitialView
//! is disabled rather than dragging the whole foreground UI into the glance's
//! 64 KB pool. See docs/STUDY.md for the annotation trade-off and the fallback
//! if the glance build overruns its budget.
(:glance)
class EssOpiApp extends Application.AppBase {

    (:glance)
    public function initialize() {
        AppBase.initialize();
    }

    (:glance)
    public function onStart(state as Dictionary?) as Void {
    }

    (:glance)
    public function onStop(state as Dictionary?) as Void {
    }

    //! Full-screen entry point: the six-page operations view.
    (:typecheck(disableGlanceCheck))
    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new EssPageView(new EssModel());
        return [view, new EssPageDelegate(view)];
    }

    //! Glance entry point. Runs in a much smaller memory pool and shares only
    //! the (:glance)-annotated modules with the foreground view.
    (:glance)
    public function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [new EssGlanceView()];
    }
}
