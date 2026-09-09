#include "PlaybackWatchdog.hpp"

#include <algorithm>
#include <cmath>

namespace ytkace {

PlaybackWatchdog::PlaybackWatchdog(WatchdogConfig config) : config_(config) {}

void PlaybackWatchdog::setLive(bool live) { live_ = live; }

bool PlaybackWatchdog::live() const { return live_; }

WatchdogState PlaybackWatchdog::state() const { return state_; }

void PlaybackWatchdog::reset(WatchdogState state) {
    state_ = state;
    incidentAttempts_ = 0;
    positionAtSuspicion_ = -1.0;
}

void PlaybackWatchdog::pruneAttempts(double now) {
    const double cutoff = now - config_.attemptWindow;
    attemptTimes_.erase(
        std::remove_if(attemptTimes_.begin(), attemptTimes_.end(),
                       [cutoff](double stamp) { return stamp < cutoff; }),
        attemptTimes_.end());
}

int PlaybackWatchdog::attemptsInWindow(double now) const {
    const double cutoff = now - config_.attemptWindow;
    return static_cast<int>(std::count_if(
        attemptTimes_.begin(), attemptTimes_.end(),
        [cutoff](double stamp) { return stamp >= cutoff; }));
}

WatchdogAction PlaybackWatchdog::rungForAttempt(int attempt) const {
    if (attempt <= 1) return WatchdogAction::Resume;
    if (attempt == 2) return live_ ? WatchdogAction::Reload : WatchdogAction::Nudge;
    return WatchdogAction::Reload;
}

WatchdogOutcome PlaybackWatchdog::beginSuspicion(double now) {
    (void)now;
    WatchdogOutcome outcome;
    state_ = WatchdogState::Suspect;
    positionAtSuspicion_ = lastPosition_;
    outcome.armTimerIn = config_.confirmDelay;
    return outcome;
}

WatchdogOutcome PlaybackWatchdog::advanceRecovery(double now) {
    WatchdogOutcome outcome;
    pruneAttempts(now);
    if (attemptsInWindow(now) >= config_.maxAttempts) {
        state_ = WatchdogState::Surrendered;
        outcome.cancelTimers = true;
        return outcome;
    }
    state_ = WatchdogState::Recovering;
    incidentAttempts_ += 1;
    attemptTimes_.push_back(now);
    outcome.action = rungForAttempt(incidentAttempts_);
    if (incidentAttempts_ == 1) {
        outcome.armTimerIn = config_.firstBackoff;
    } else if (incidentAttempts_ == 2) {
        outcome.armTimerIn = config_.secondBackoff;
    } else {
        outcome.armTimerIn = config_.thirdBackoff;
    }
    return outcome;
}

WatchdogOutcome PlaybackWatchdog::handle(WatchdogEvent event, double now,
                                         double mediaPosition) {
    WatchdogOutcome outcome;

    switch (event) {
        case WatchdogEvent::PlaybackStarted:
            reset(WatchdogState::Watching);
            attemptTimes_.clear();
            lastPosition_ = mediaPosition;
            outcome.cancelTimers = true;
            return outcome;

        case WatchdogEvent::VideoChanged:
        case WatchdogEvent::FeatureDisabled:
            reset(WatchdogState::Idle);
            attemptTimes_.clear();
            lastPosition_ = -1.0;
            outcome.cancelTimers = true;
            return outcome;

        case WatchdogEvent::UserScrub:
        case WatchdogEvent::UserPause:
            if (state_ == WatchdogState::Idle ||
                state_ == WatchdogState::Surrendered) {
                return outcome;
            }
            reset(WatchdogState::Watching);
            lastPosition_ = mediaPosition;
            outcome.cancelTimers = true;
            return outcome;

        case WatchdogEvent::ProgressObserved: {
            const bool advanced =
                lastPosition_ < 0.0 ||
                (mediaPosition - lastPosition_) >= config_.progressEpsilon;
            if (mediaPosition >= 0.0) lastPosition_ = mediaPosition;
            if (!advanced) return outcome;
            if (state_ == WatchdogState::Suspect) {
                reset(WatchdogState::Watching);
                outcome.cancelTimers = true;
            } else if (state_ == WatchdogState::Recovering) {
                reset(WatchdogState::Cooldown);
                outcome.cancelTimers = true;
                outcome.armTimerIn = config_.cooldown;
            }
            return outcome;
        }

        case WatchdogEvent::ErrorReported:
        case WatchdogEvent::ServerStop:
        case WatchdogEvent::StalledState:
            if (state_ == WatchdogState::Watching) return beginSuspicion(now);
            return outcome;

        case WatchdogEvent::TimerFired:
            if (state_ == WatchdogState::Cooldown) {
                reset(WatchdogState::Watching);
                attemptTimes_.clear();
                return outcome;
            }
            if (state_ == WatchdogState::Suspect) {
                const bool progressed =
                    positionAtSuspicion_ >= 0.0 && lastPosition_ >= 0.0 &&
                    (lastPosition_ - positionAtSuspicion_) >= config_.progressEpsilon;
                if (progressed) {
                    reset(WatchdogState::Watching);
                    outcome.cancelTimers = true;
                    return outcome;
                }
                return advanceRecovery(now);
            }
            if (state_ == WatchdogState::Recovering) return advanceRecovery(now);
            return outcome;
    }

    return outcome;
}

}
