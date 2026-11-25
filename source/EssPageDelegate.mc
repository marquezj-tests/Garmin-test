import Toybox.Lang;
import Toybox.WatchUi;

//! Input handling for the full-screen view.
//!
//! On the Forerunner 265 the up/down buttons and vertical swipes both arrive
//! as onNextPage / onPreviousPage behaviours, so handling those two covers
//! button and touch navigation without writing separate gesture code.
class EssPageDelegate extends WatchUi.BehaviorDelegate {

    private var _view as EssPageView;

    public function initialize(view as EssPageView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    //! START / tap: force an immediate re-poll.
    public function onSelect() as Boolean {
        _view.refresh();
        return true;
    }

    public function onNextPage() as Boolean {
        _view.nextPage();
        return true;
    }

    public function onPreviousPage() as Boolean {
        _view.previousPage();
        return true;
    }
}
