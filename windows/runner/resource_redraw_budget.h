#ifndef RUNNER_RESOURCE_REDRAW_BUDGET_H_
#define RUNNER_RESOURCE_REDRAW_BUDGET_H_

#include <cstdint>

// Pure policy: milliseconds come from GetTickCount64 in the runner. Tests use
// explicit clock values. This counts requests, not rendered/presented frames.
class ResourceRedrawBudget {
 public:
  static constexpr std::uint64_t kDurationMilliseconds = 1000;
  static constexpr int kMaximumRequests = 60;

  bool Start(std::uint64_t now) {
    if (used_) return false;
    used_ = true;
    active_ = true;
    started_ = now;
    return true;
  }

  bool TakeRequest(std::uint64_t now) {
    if (!active_) return false;
    if (now < started_ || now - started_ >= kDurationMilliseconds ||
        requests_ >= kMaximumRequests) {
      Stop();
      return false;
    }
    ++requests_;
    return true;
  }

  void Stop() { active_ = false; }
  bool active() const { return active_; }
  bool used() const { return used_; }
  int requests() const { return requests_; }

 private:
  bool used_ = false;
  bool active_ = false;
  std::uint64_t started_ = 0;
  int requests_ = 0;
};

#endif
