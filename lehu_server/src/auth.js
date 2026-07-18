import crypto from 'node:crypto';

const sessions = new Map();

function sessionTtlMs() {
  const hours = Number.parseInt(process.env.SESSION_TTL_HOURS ?? '168', 10);
  const safeHours = Number.isFinite(hours) && hours > 0 ? hours : 168;
  return safeHours * 60 * 60 * 1000;
}

function cookieSecure() {
  const value = String(process.env.COOKIE_SECURE ?? '').toLowerCase();
  return value === '1' || value === 'true';
}

function getAdminPassword() {
  return process.env.ADMIN_PASSWORD ?? 'change-this-password';
}

function createSessionToken() {
  return crypto.randomBytes(32).toString('hex');
}

function validateAdminPassword(password) {
  return String(password ?? '') === getAdminPassword();
}

function registerAdminSession(res) {
  const token = createSessionToken();
  sessions.set(token, {
    expiresAt: Date.now() + sessionTtlMs()
  });

  res.cookie('lehu_admin_session', token, {
    signed: true,
    httpOnly: true,
    sameSite: 'lax',
    secure: cookieSecure(),
    maxAge: sessionTtlMs(),
    path: '/'
  });

  return token;
}

function clearAdminSession(res, token) {
  if (token) {
    sessions.delete(token);
  }

  res.clearCookie('lehu_admin_session', { path: '/' });
}

function getSessionToken(req) {
  return req.signedCookies?.lehu_admin_session ?? req.cookies?.lehu_admin_session;
}

function isAdminAuthenticated(req) {
  const token = getSessionToken(req);
  if (!token) {
    return false;
  }

  const session = sessions.get(token);
  if (!session) {
    return false;
  }

  if (session.expiresAt <= Date.now()) {
    sessions.delete(token);
    return false;
  }

  return true;
}

function requireAdmin(req, res, next) {
  if (isAdminAuthenticated(req)) {
    next();
    return;
  }

  if (req.path.startsWith('/api/')) {
    res.status(401).json({
      success: false,
      error: 'Unauthorized'
    });
    return;
  }

  res.redirect('/admin/login');
}

function cleanupSessions() {
  const now = Date.now();
  for (const [token, session] of sessions.entries()) {
    if (session.expiresAt <= now) {
      sessions.delete(token);
    }
  }
}

setInterval(cleanupSessions, 15 * 60 * 1000).unref();

export {
  clearAdminSession,
  getSessionToken,
  isAdminAuthenticated,
  registerAdminSession,
  requireAdmin,
  validateAdminPassword
};
