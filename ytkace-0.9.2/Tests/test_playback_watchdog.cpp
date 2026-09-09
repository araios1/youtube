#include "../Tweak/Features/Playback/PlaybackWatchdog.hpp"

#include <cstdio>
#include <string>

using namespace ytkace;

static int failureCount = 0;
static std::string currentCase;

static void expect(bool condition, const std::string &what) {
    if (condition) return;
    failureCount += 1;
    std::printf("  FAIL [%s] %s\n", currentCase.c_str(), what.c_str());
}

static const char *actionName(WatchdogAction action) {
    switch (action) {
        case WatchdogAction::None: return "None";
        case WatchdogAction::Resume: return "Resume";
        case WatchdogAction::Nudge: return "Nudge";
        case WatchdogAction::Reload: return "Reload";
    }
    return "?";
}

static void expectAction(WatchdogAction got, WatchdogAction want,
                         const std::string &what) {
    if (got == want) return;
    failureCount += 1;
    std::printf("  FAIL [%s] %s: got %s want %s\n", currentCase.c_str(), what.c_str(),
                actionName(got), actionName(want));
}

static void begin(const char *name) {
    currentCase = name;
    std::printf("- %s\n", name);
}

static PlaybackWatchdog started(double at = 0.0) {
    PlaybackWatchdog dog;
    dog.handle(WatchdogEvent::PlaybackStarted, at, 0.0);
    return dog;
}

static void testStall() {
    begin("stall enters recovery after the confirmation delay");
    PlaybackWatchdog dog = started();
    WatchdogOutcome suspect = dog.handle(WatchdogEvent::StalledState, 10.0);
    expect(dog.state() == WatchdogState::Suspect, "state is Suspect");
    expect(suspect.armTimerIn > 1.0 && suspect.armTimerIn < 2.0, "confirm timer armed");
    expectAction(suspect.action, WatchdogAction::None, "no action before confirmation");
    WatchdogOutcome fired = dog.handle(WatchdogEvent::TimerFired, 11.2);
    expect(dog.state() == WatchdogState::Recovering, "state is Recovering");
    expectAction(fired.action, WatchdogAction::Resume, "first rung is Resume");
}

static void testFalseAlarm() {
    begin("progress before confirmation cancels with no action");
    PlaybackWatchdog dog = started();
    dog.handle(WatchdogEvent::ErrorReported, 10.0);
    WatchdogOutcome progress = dog.handle(WatchdogEvent::ProgressObserved, 10.5, 1.0);
    expect(dog.state() == WatchdogState::Watching, "back to Watching");
    expect(progress.cancelTimers, "timers cancelled");
    expectAction(progress.action, WatchdogAction::None, "no recovery action");
}

static void testRetryLadder() {
    begin("retry ladder runs Resume, Nudge, Reload with growing backoff");
    PlaybackWatchdog dog = started();
    dog.handle(WatchdogEvent::StalledState, 10.0);
    WatchdogOutcome first = dog.handle(WatchdogEvent::TimerFired, 11.2);
    expectAction(first.action, WatchdogAction::Resume, "attempt 1");
    expect(first.armTimerIn == 2.0, "first backoff is 2s");
    WatchdogOutcome second = dog.handle(WatchdogEvent::TimerFired, 13.2);
    expectAction(second.action, WatchdogAction::Nudge, "attempt 2");
    expect(second.armTimerIn == 6.0, "second backoff is 6s");
    WatchdogOutcome third = dog.handle(WatchdogEvent::TimerFired, 19.2);
    expectAction(third.action, WatchdogAction::Reload, "attempt 3");
    expect(third.armTimerIn == 18.0, "third backoff is 18s");
}

static void testBudget() {
    begin("budget exhaustion surrenders to the host app");
    PlaybackWatchdog dog = started();
    dog.handle(WatchdogEvent::StalledState, 10.0);
    dog.handle(WatchdogEvent::TimerFired, 11.2);
    dog.handle(WatchdogEvent::TimerFired, 13.2);
    dog.handle(WatchdogEvent::TimerFired, 19.2);
    WatchdogOutcome fourth = dog.handle(WatchdogEvent::TimerFired, 37.2);
    expect(dog.state() == WatchdogState::Surrendered, "state is Surrendered");
    expectAction(fourth.action, WatchdogAction::None, "no fourth action");
    expect(fourth.cancelTimers, "timers cancelled on surrender");
    WatchdogOutcome ignored = dog.handle(WatchdogEvent::ErrorReported, 40.0);
    expectAction(ignored.action, WatchdogAction::None, "errors ignored after surrender");
    expect(dog.state() == WatchdogState::Surrendered, "stays Surrendered");
}

static void testRecovery() {
    begin("progress during recovery enters cooldown and restores budget");
    PlaybackWatchdog dog = started();
    dog.handle(WatchdogEvent::StalledState, 10.0);
    dog.handle(WatchdogEvent::TimerFired, 11.2);
    WatchdogOutcome recovered = dog.handle(WatchdogEvent::ProgressObserved, 12.0, 5.0);
    expect(dog.state() == WatchdogState::Cooldown, "state is Cooldown");
    expect(recovered.armTimerIn == 30.0, "cooldown timer armed");
    expect(dog.attemptsInWindow(12.0) == 1, "attempt still counted during cooldown");
    dog.handle(WatchdogEvent::TimerFired, 42.0);
    expect(dog.state() == WatchdogState::Watching, "cooldown ends in Watching");
    expect(dog.attemptsInWindow(42.0) == 0, "budget restored after cooldown");
}

static void testScrubbing() {
    begin("user scrubbing cancels pending recovery immediately");
    PlaybackWatchdog dog = started();
    dog.handle(WatchdogEvent::StalledState, 10.0);
    WatchdogOutcome scrub = dog.handle(WatchdogEvent::UserScrub, 10.4, 30.0);
    expect(dog.state() == WatchdogState::Watching, "scrub returns to Watching");
    expect(scrub.cancelTimers, "timers cancelled");
    WatchdogOutcome after = dog.handle(WatchdogEvent::TimerFired, 11.2);
    expectAction(after.action, WatchdogAction::None, "stale timer does nothing");

    PlaybackWatchdog other = started();
    other.handle(WatchdogEvent::StalledState, 10.0);
    other.handle(WatchdogEvent::TimerFired, 11.2);
    WatchdogOutcome midScrub = other.handle(WatchdogEvent::UserScrub, 11.5, 30.0);
    expect(other.state() == WatchdogState::Watching, "scrub during recovery cancels");
    expect(midScrub.cancelTimers, "recovery timers cancelled");
}

static void testLive() {
    begin("live playback never nudges and reloads instead");
    PlaybackWatchdog dog = started();
    dog.setLive(true);
    dog.handle(WatchdogEvent::StalledState, 10.0);
    WatchdogOutcome first = dog.handle(WatchdogEvent::TimerFired, 11.2);
    expectAction(first.action, WatchdogAction::Resume, "attempt 1 is Resume");
    WatchdogOutcome second = dog.handle(WatchdogEvent::TimerFired, 13.2);
    expectAction(second.action, WatchdogAction::Reload, "attempt 2 is Reload, not Nudge");
    WatchdogOutcome third = dog.handle(WatchdogEvent::TimerFired, 19.2);
    expectAction(third.action, WatchdogAction::Reload, "attempt 3 is Reload");
}

static void testCancellation() {
    begin("video change and feature disable both cancel and idle");
    PlaybackWatchdog dog = started();
    dog.handle(WatchdogEvent::StalledState, 10.0);
    WatchdogOutcome changed = dog.handle(WatchdogEvent::VideoChanged, 10.5);
    expect(dog.state() == WatchdogState::Idle, "video change idles");
    expect(changed.cancelTimers, "timers cancelled");

    PlaybackWatchdog other = started();
    other.handle(WatchdogEvent::StalledState, 10.0);
    other.handle(WatchdogEvent::TimerFired, 11.2);
    WatchdogOutcome disabled = other.handle(WatchdogEvent::FeatureDisabled, 12.0);
    expect(other.state() == WatchdogState::Idle, "feature disable idles");
    expect(disabled.cancelTimers, "timers cancelled");
    WatchdogOutcome quiet = other.handle(WatchdogEvent::ErrorReported, 13.0);
    expectAction(quiet.action, WatchdogAction::None, "no action while idle");
}

static void testFlap() {
    begin("flapping faults do not consume the attempt budget");
    PlaybackWatchdog dog = started();
    double position = 0.0;
    for (int i = 0; i < 12; ++i) {
        const double base = 10.0 + i * 5.0;
        dog.handle(WatchdogEvent::ErrorReported, base);
        position += 1.0;
        dog.handle(WatchdogEvent::ProgressObserved, base + 0.5, position);
    }
    expect(dog.attemptsInWindow(70.0) == 0, "no attempts consumed");
    expect(dog.state() == WatchdogState::Watching, "still Watching");
}

static void testCooldownIgnoresFaults() {
    begin("faults during cooldown are ignored and not counted");
    PlaybackWatchdog dog = started();
    dog.handle(WatchdogEvent::StalledState, 10.0);
    dog.handle(WatchdogEvent::TimerFired, 11.2);
    dog.handle(WatchdogEvent::ProgressObserved, 12.0, 5.0);
    expect(dog.state() == WatchdogState::Cooldown, "in cooldown");
    WatchdogOutcome fault = dog.handle(WatchdogEvent::ErrorReported, 15.0);
    expectAction(fault.action, WatchdogAction::None, "no action during cooldown");
    expect(dog.state() == WatchdogState::Cooldown, "stays in cooldown");
    expect(dog.attemptsInWindow(15.0) == 1, "budget unchanged");
}

static void testHeartbeatIsNotAFault() {
    begin("routine progress at heartbeat cadence never arms recovery");
    PlaybackWatchdog dog = started();
    for (int i = 1; i <= 5; ++i) {
        const double now = i * 60.0;
        dog.handle(WatchdogEvent::ProgressObserved, now, now);
        expect(dog.state() == WatchdogState::Watching, "still Watching at heartbeat");
    }
    expect(dog.attemptsInWindow(300.0) == 0, "no recovery attempted");
}

int main() {
    std::printf("PlaybackWatchdog\n");
    testStall();
    testFalseAlarm();
    testRetryLadder();
    testBudget();
    testRecovery();
    testScrubbing();
    testLive();
    testCancellation();
    testFlap();
    testCooldownIgnoresFaults();
    testHeartbeatIsNotAFault();
    if (failureCount == 0) {
        std::printf("all tests passed\n");
        return 0;
    }
    std::printf("%d failure(s)\n", failureCount);
    return 1;
}
