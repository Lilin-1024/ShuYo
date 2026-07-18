export function createRateLimit({
  windowMs,
  max,
  keyFn = (req) => req.ip,
  message = 'Too many requests'
}) {
  const buckets = new Map();

  function cleanup() {
    const now = Date.now();
    for (const [key, bucket] of buckets.entries()) {
      if (bucket.resetAt <= now) {
        buckets.delete(key);
      }
    }
  }

  const timer = setInterval(cleanup, Math.max(windowMs, 60_000));
  timer.unref();

  return (req, res, next) => {
    const key = keyFn(req);
    const now = Date.now();
    let bucket = buckets.get(key);

    if (!bucket || bucket.resetAt <= now) {
      bucket = {
        count: 0,
        resetAt: now + windowMs
      };
      buckets.set(key, bucket);
    }

    bucket.count += 1;

    res.setHeader('X-RateLimit-Limit', String(max));
    res.setHeader('X-RateLimit-Remaining', String(Math.max(max - bucket.count, 0)));
    res.setHeader('X-RateLimit-Reset', String(bucket.resetAt));

    if (bucket.count > max) {
      res.status(429).json({
        success: false,
        error: message
      });
      return;
    }

    next();
  };
}
