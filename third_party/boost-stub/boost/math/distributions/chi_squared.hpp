// Minimal stub: chi-squared distribution used for MSCKF/SLAM gating tests.
// Provides just enough for the chi_squared_distribution<double> usage in
// UpdaterMSCKF.cpp / UpdaterSLAM.cpp / StateHelper.cpp.
#pragma once
#include <cmath>

namespace boost {
namespace math {

template <typename RealType = double>
struct chi_squared_distribution {
    explicit chi_squared_distribution(RealType df) : df_(df) {}
    RealType degrees_of_freedom() const { return df_; }
private:
    RealType df_;
};

namespace detail {
// Rational approximation of the inverse error function (Winitzki 2008).
// Accurate to ~3e-3 relative error, sufficient for chi-sq gating thresholds.
inline double erfinv_approx(double x) {
    const double a = 0.147;
    const double ln = std::log(1.0 - x * x);
    const double t = 2.0 / (M_PI * a) + ln / 2.0;
    double s = std::sqrt(std::sqrt(t * t - ln / a) - t);
    return (x < 0.0) ? -s : s;
}
} // namespace detail

template <typename RealType>
RealType quantile(const chi_squared_distribution<RealType> &dist, RealType p) {
    // Wilson–Hilferty approximation for chi-squared quantile.
    RealType k = dist.degrees_of_freedom();
    RealType h = 1.0 - 2.0 / (9.0 * k);
    RealType z = std::sqrt(2.0) * detail::erfinv_approx(2.0 * p - 1.0);
    RealType tmp = h + z * std::sqrt(2.0 / (9.0 * k));
    return k * tmp * tmp * tmp;
}

} // namespace math
} // namespace boost
