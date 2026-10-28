/// Reading size is presentation-only and independent of Planner sizing.
double normalizeOpportunitiesContentScale(Object? value) =>
    value is num && value.isFinite ? value.toDouble().clamp(1.0, 1.25) : 1;
