// Minimal Boost.DateTime/posix_time stub for iOS builds.
// ptime is used only for internal timing/logging; stub returns zeroed durations.
#pragma once

namespace boost {
namespace posix_time {

struct time_duration {
    long total_microseconds() const { return 0; }
    double total_seconds() const { return 0.0; }
};

struct ptime {
    ptime() = default;
    time_duration operator-(const ptime &) const { return {}; }
};

struct microsec_clock {
    static ptime local_time() { return {}; }
};

} // namespace posix_time
} // namespace boost
