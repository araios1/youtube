#pragma once

#include <cstddef>
#include <vector>

namespace ytkace {

enum class WatchdogState {
    Idle,
    Watching,
    Suspect,
    Recovering,
    Cooldown,
    Surrendered
};

enum class WatchdogEvent {
    PlaybackStarted,
    ProgressObserved,
    ErrorReported,
    ServerStop,
    StalledState,
    UserScrub,
    UserPause,
    VideoChanged,
    FeatureDisabled,
    TimerFired
};

enum class WatchdogAction {
    None,
    Resume,
    Nudge,
    Reload
};

struct WatchdogConfig {
    double confirmDelay = 1.2;
    double firstBackoff = 2.0;
    double secondBackoff = 6.0;
    double thirdBackoff = 18.0;
    double attemptWindow = 90.0;
    double cooldown = 30.0;
    double progressEpsilon = 0.25;
    int maxAttempts = 3;
};

struct WatchdogOutcome {
    WatchdogAction action = WatchdogAction::None;
    double armTimerIn = -1.0;
    bool cancelTimers = false;
};

class PlaybackWatchdog {
public:
    explicit PlaybackWatchdog(WatchdogConfig config = WatchdogConfig());

    WatchdogOutcome handle(WatchdogEvent event, double now, double mediaPosition = -1.0);

    void setLive(bool live);
    bool live() const;
    WatchdogState state() const;
    int attemptsInWindow(double now) const;

private:
    WatchdogOutcome beginSuspicion(double now);
    WatchdogOutcome advanceRecovery(double now);
    WatchdogAction rungForAttempt(int attempt) const;
    void pruneAttempts(double now);
    void reset(WatchdogState state);

    WatchdogConfig config_;
    WatchdogState state_ = WatchdogState::Idle;
    bool live_ = false;
    int incidentAttempts_ = 0;
    double lastPosition_ = -1.0;
    double positionAtSuspicion_ = -1.0;
    std::vector<double> attemptTimes_;
};

}
