// Minimal Boost.Filesystem stub for iOS builds.
// boost::filesystem functions are gated by OPENVINS_DISABLE_FILE_OUTPUT and
// are never called at runtime. This stub satisfies compiler type requirements.
#pragma once
#include <string>

namespace boost {
namespace filesystem {

struct path {
    path() = default;
    path(const char *p) : str_(p) {}        // NOLINT: implicit by design (matches Boost API)
    path(const std::string &p) : str_(p) {} // NOLINT
    path parent_path() const { return path{}; }
    const std::string &string() const { return str_; }
    const char *c_str() const { return str_.c_str(); }
private:
    std::string str_;
};

inline bool exists(const path &) { return false; }
inline bool remove(const path &) { return false; }
inline void create_directories(const path &) {}

} // namespace filesystem
} // namespace boost
