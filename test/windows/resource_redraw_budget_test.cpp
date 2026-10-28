#include <cstdint>
#include <initializer_list>
#include <iostream>
#include <limits>
#include <string>

#include "resource_redraw_budget.h"

namespace {
int checks = 0;
int failures = 0;

void Check(bool condition, const std::string& description) {
  ++checks;
  if (!condition) {
    ++failures;
    std::cerr << "FAIL " << description << '\n';
  }
}

void InitialAndUnusedStop() {
  ResourceRedrawBudget budget;
  Check(!budget.active() && !budget.used() && budget.requests() == 0,
        "new budget is inactive and unused");
  Check(!budget.TakeRequest(0), "tick before start does nothing");
  budget.Stop();
  budget.Stop();
  Check(!budget.used(), "stopping an unused budget does not consume it");
  Check(budget.Start(0), "unused budget can still start at clock origin");
  Check(budget.TakeRequest(0), "clock origin is a valid first request");
}

void EveryEligibleMillisecond() {
  constexpr std::uint64_t start = 12345;
  for (std::uint64_t elapsed = 0; elapsed < 1000; ++elapsed) {
    ResourceRedrawBudget budget;
    const auto label = std::to_string(elapsed) + "ms";
    Check(budget.Start(start), "fresh start for " + label);
    Check(budget.TakeRequest(start + elapsed),
          "each elapsed value 0..999ms permits one request: " + label);
    Check(budget.requests() == 1 && budget.used() && budget.active(),
          "one request is accounted for at " + label);
    Check(!budget.TakeRequest(start + 1000),
          "exact deadline rejects after eligible request at " + label);
    Check(!budget.active() && budget.requests() == 1,
          "deadline stops without adding a request at " + label);
    Check(!budget.Start(start + 1001),
          "completed attempt cannot restart after " + label);
  }
}

void RequestCapAndNoDeadlineExtension() {
  ResourceRedrawBudget budget;
  Check(budget.Start(5000), "cap case starts");
  for (int index = 0; index < 60; ++index) {
    Check(budget.TakeRequest(5000),
          "repeated timestamp cannot evade request accounting");
    Check(budget.requests() == index + 1, "request count increments once");
  }
  Check(!budget.TakeRequest(5000), "61st request is rejected even before deadline");
  Check(!budget.active() && budget.requests() == 60,
        "request cap deactivates without overflow");
  Check(!budget.Start(5001), "request-cap completion cannot restart");

  ResourceRedrawBudget repeated_start;
  Check(repeated_start.Start(8000), "duplicate-start case starts");
  Check(repeated_start.TakeRequest(8100), "duplicate-start case has a request");
  Check(!repeated_start.Start(8999), "second start is refused while active");
  Check(repeated_start.requests() == 1, "second start does not reset request count");
  Check(!repeated_start.TakeRequest(9000), "second start cannot extend deadline");
}

void RegularAndDelayedTicks() {
  ResourceRedrawBudget regular;
  Check(regular.Start(10000), "regular cadence starts");
  for (int index = 0; index < 60; ++index) {
    Check(regular.TakeRequest(10000 + static_cast<std::uint64_t>(index) * 16),
          "16ms cadence permits at most 60 requests");
  }
  Check(!regular.TakeRequest(10960), "regular cadence stops on cap before 1s");
  Check(regular.requests() == 60, "regular cadence issued exactly 60 requests");

  for (const std::uint64_t elapsed : {1000ULL, 1001ULL, 5000ULL, 60000ULL}) {
    ResourceRedrawBudget delayed;
    Check(delayed.Start(100), "delayed tick starts");
    Check(!delayed.TakeRequest(100 + elapsed),
          "delayed first tick never catches up at " + std::to_string(elapsed));
    Check(delayed.requests() == 0 && !delayed.active(),
          "expired first tick issues no redraw requests");
    Check(!delayed.Start(100 + elapsed), "expiry consumes the one attempt");
  }
}

void CancellationAndFailedTimerModel() {
  ResourceRedrawBudget cancelled;
  Check(cancelled.Start(2000), "cancellation case starts");
  Check(cancelled.TakeRequest(2001), "one request precedes cancellation");
  cancelled.Stop();
  cancelled.Stop();
  for (const std::uint64_t now : {2001ULL, 2016ULL, 2999ULL, 3000ULL, 99999ULL}) {
    Check(!cancelled.TakeRequest(now), "queued tick after stop cannot redraw");
  }
  Check(cancelled.requests() == 1 && !cancelled.active() && cancelled.used(),
        "cancellation preserves accounting and consumed state");
  Check(!cancelled.Start(4000), "cancelled attempt cannot restart");

  // Models the runner's Start -> failed SetTimer -> Stop sequence. This pure
  // policy test deliberately does not create an HWND or call a native timer.
  ResourceRedrawBudget failed_timer;
  Check(failed_timer.Start(6000), "timer-failure model consumes start");
  failed_timer.Stop();
  Check(!failed_timer.TakeRequest(6000), "failed timer model permits no request");
  Check(failed_timer.requests() == 0 && failed_timer.used(),
        "failed timer model remains consumed with zero requests");
  Check(!failed_timer.Start(6001), "failed timer attempt cannot retry");
}

void BackwardAndExtremeClockValues() {
  ResourceRedrawBudget backward;
  Check(backward.Start(1000), "backward-clock case starts");
  Check(!backward.TakeRequest(999), "time before start stops safely");
  Check(!backward.active() && backward.requests() == 0,
        "backward clock does not unsigned-underflow into eligibility");
  Check(!backward.TakeRequest(1000), "clock recovery does not revive stopped run");
  Check(!backward.Start(2000), "backward-clock stop cannot restart");

  // GetTickCount64 is monotonic in production. Even a synthetic backwards
  // sequence that stays above the origin cannot evade the independent cap.
  ResourceRedrawBudget non_monotonic;
  Check(non_monotonic.Start(0), "non-monotonic bounded case starts");
  for (int index = 0; index < 60; ++index) {
    Check(non_monotonic.TakeRequest(index % 2 == 0 ? 999 : 0),
          "synthetic backwards timestamps remain request-budgeted");
  }
  Check(!non_monotonic.TakeRequest(0) && non_monotonic.requests() == 60,
        "non-monotonic inputs cannot exceed 60 requests");

  constexpr auto maximum = (std::numeric_limits<std::uint64_t>::max)();
  ResourceRedrawBudget large_clock;
  Check(large_clock.Start(maximum - 1000), "large monotonic clock starts");
  Check(large_clock.TakeRequest(maximum - 1), "999ms remains valid near uint64 max");
  Check(!large_clock.TakeRequest(maximum), "1000ms expires near uint64 max");

  ResourceRedrawBudget wrapped_clock;
  Check(wrapped_clock.Start(maximum - 1), "wrap-defense case starts");
  Check(wrapped_clock.TakeRequest(maximum), "last representable clock tick works");
  Check(!wrapped_clock.TakeRequest(0), "clock wrap is rejected as backwards");
  Check(wrapped_clock.requests() == 1 && !wrapped_clock.active(),
        "wrap cannot extend an active run");
}
}  // namespace

int main() {
  static_assert(ResourceRedrawBudget::kDurationMilliseconds == 1000,
                "The approved diagnostic is bounded to one second.");
  static_assert(ResourceRedrawBudget::kMaximumRequests == 60,
                "The approved diagnostic permits at most 60 requests.");
  InitialAndUnusedStop();
  EveryEligibleMillisecond();
  RequestCapAndNoDeadlineExtension();
  RegularAndDelayedTicks();
  CancellationAndFailedTimerModel();
  BackwardAndExtremeClockValues();
  std::cout << "Resource redraw pure budget: " << checks << " checks, "
            << failures << " failures. No windows, timers or renderer started.\n";
  return failures == 0 ? 0 : 1;
}
