import crypto from 'node:crypto';
import express from 'express';
import cookieParser from 'cookie-parser';
import helmet from 'helmet';
import morgan from 'morgan';

import {
  clearAdminSession,
  isAdminAuthenticated,
  registerAdminSession,
  requireAdmin,
  validateAdminPassword
} from './auth.js';
import { createRateLimit } from './rateLimit.js';
import { hashToken, makeId, mutateState, nowIso, readState } from './store.js';
import { renderDashboard, renderFeedbackDetail, renderLoginPage } from './views.js';

const app = express();
const port = Number.parseInt(process.env.PORT ?? '3000', 10) || 3000;

app.set('trust proxy', 1);
app.disable('x-powered-by');
app.use(helmet({ contentSecurityPolicy: false }));
app.use(morgan('combined'));
app.use(cookieParser(process.env.COOKIE_SECRET ?? 'change-this-cookie-secret'));
app.use(express.json({ limit: '64kb' }));
app.use(express.urlencoded({ extended: false, limit: '64kb' }));

const feedbackRateLimit = createRateLimit({
  windowMs: 10 * 60 * 1000,
  max: 5,
  message: '反馈提交过于频繁，请稍后再试。'
});

const loginRateLimit = createRateLimit({
  windowMs: 10 * 60 * 1000,
  max: 10,
  message: '登录尝试过于频繁，请稍后再试。'
});

function jsonEtag(value) {
  return `"${crypto.createHash('sha1').update(JSON.stringify(value)).digest('hex')}"`;
}

function sendCachedJson(req, res, payload, maxAgeSeconds = 60) {
  const etag = jsonEtag(payload);
  res.setHeader('Cache-Control', `public, max-age=${maxAgeSeconds}`);
  res.setHeader('ETag', etag);

  if (req.headers['if-none-match'] === etag) {
    res.status(304).end();
    return;
  }

  res.json(payload);
}

function isTruthy(value) {
  return ['1', 'true', 'yes', 'on'].includes(String(value ?? '').toLowerCase());
}

function trimText(value) {
  return String(value ?? '').trim();
}

function validateLength(value, max, label) {
  if (value.length > max) {
    throw new Error(`${label} 不能超过 ${max} 个字符`);
  }
}

function selectLatestAnnouncement(announcements) {
  const active = announcements
    .filter((item) => item.active !== false)
    .sort((a, b) => String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? '')));

  return active[0] ?? null;
}

function publicAnnouncement(item) {
  if (!item) {
    return null;
  }

  return {
    id: item.id,
    title: item.title,
    content: item.content,
    active: item.active !== false,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt
  };
}

function publicFeedback(item) {
  return {
    id: item.id,
    title: item.title,
    content: item.content,
    contact: item.contact ?? '',
    deviceId: item.deviceId ?? '',
    appVersion: item.appVersion ?? '',
    platform: item.platform ?? '',
    status: item.status,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
    replies: (item.replies ?? []).map((reply) => ({
      id: reply.id,
      author: reply.author,
      message: reply.message,
      createdAt: reply.createdAt
    }))
  };
}

function publicVersionPayload(state) {
  const latestAnnouncement = selectLatestAnnouncement(state.announcements);
  return {
    success: true,
    data: {
      appName: state.meta.appName,
      latestVersion: state.meta.latestVersion,
      latestBuild: state.meta.latestBuild,
      forceUpdate: state.meta.forceUpdate,
      updateTitle: state.meta.updateTitle,
      updateMessage: state.meta.updateMessage,
      downloadUrl: state.meta.downloadUrl,
      noticeText: state.meta.noticeText,
      publishedAt: state.meta.publishedAt,
      updatedAt: state.meta.updatedAt,
      announcement: publicAnnouncement(latestAnnouncement)
    }
  };
}

async function getFeedbackById(id) {
  const state = await readState();
  return {
    state,
    item: state.feedback.find((feedback) => feedback.id === id) ?? null
  };
}

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    service: 'lehu-update-feedback-server',
    time: nowIso()
  });
});

app.get('/api/v1/version', async (req, res, next) => {
  try {
    const state = await readState();
    sendCachedJson(req, res, publicVersionPayload(state), 120);
  } catch (error) {
    next(error);
  }
});

app.get('/api/v1/announcements/latest', async (req, res, next) => {
  try {
    const state = await readState();
    const latest = selectLatestAnnouncement(state.announcements);
    sendCachedJson(
      req,
      res,
      {
        success: true,
        data: publicAnnouncement(latest)
      },
      300
    );
  } catch (error) {
    next(error);
  }
});

app.get('/api/v1/bootstrap', async (req, res, next) => {
  try {
    const state = await readState();
    sendCachedJson(
      req,
      res,
      {
        success: true,
        data: {
          version: publicVersionPayload(state).data,
          latestAnnouncement: publicAnnouncement(selectLatestAnnouncement(state.announcements))
        }
      },
      120
    );
  } catch (error) {
    next(error);
  }
});

app.post('/api/v1/feedback', feedbackRateLimit, async (req, res, next) => {
  try {
    const title = trimText(req.body.title ?? '');
    const content = trimText(req.body.content ?? '');
    const contact = trimText(req.body.contact ?? '');
    const deviceId = trimText(req.body.deviceId ?? '');
    const appVersion = trimText(req.body.appVersion ?? '');
    const platform = trimText(req.body.platform ?? '');

    if (!content) {
      res.status(400).json({
        success: false,
        error: '反馈内容不能为空。'
      });
      return;
    }

    validateLength(title, 120, '标题');
    validateLength(content, 4000, '内容');
    validateLength(contact, 120, '联系方式');
    validateLength(deviceId, 120, '设备标识');
    validateLength(appVersion, 60, '客户端版本');
    validateLength(platform, 60, '平台信息');

    const createdAt = nowIso();
    const lookupToken = crypto.randomBytes(24).toString('hex');
    const tokenHash = hashToken(lookupToken);
    const feedback = {
      id: makeId('fb'),
      tokenHash,
      title: title || '未命名反馈',
      content,
      contact,
      deviceId,
      appVersion,
      platform,
      status: 'open',
      createdAt,
      updatedAt: createdAt,
      replies: []
    };

    await mutateState((state) => {
      state.feedback.unshift(feedback);
    });

    res.status(201).json({
      success: true,
      data: {
        id: feedback.id,
        lookupToken,
        status: feedback.status,
        createdAt: feedback.createdAt
      }
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/v1/feedback/:id', async (req, res, next) => {
  try {
    const { item } = await getFeedbackById(req.params.id);
    if (!item) {
      res.status(404).json({
        success: false,
        error: '未找到反馈。'
      });
      return;
    }

    const token =
      trimText(req.query.token ?? '') ||
      trimText(req.get('x-feedback-token') ?? '') ||
      trimText((req.get('authorization') ?? '').replace(/^Bearer\s+/i, ''));

    if (!token || hashToken(token) !== item.tokenHash) {
      res.status(403).json({
        success: false,
        error: '验证失败。'
      });
      return;
    }

    res.json({
      success: true,
      data: publicFeedback(item)
    });
  } catch (error) {
    next(error);
  }
});

app.get('/admin/login', (req, res) => {
  if (isAdminAuthenticated(req)) {
    res.redirect('/admin');
    return;
  }

  res.status(200).send(renderLoginPage());
});

app.post('/admin/login', loginRateLimit, async (req, res) => {
  const password = trimText(req.body.password ?? '');

  if (!validateAdminPassword(password)) {
    res.status(401).send(renderLoginPage({ errorMessage: '密码错误，请重试。' }));
    return;
  }

  registerAdminSession(res);
  res.redirect('/admin');
});

app.post('/admin/logout', (req, res) => {
  const token = req.cookies?.lehu_admin_session;
  clearAdminSession(res, token);
  res.redirect('/admin/login');
});

app.get('/admin/logout', (req, res) => {
  const token = req.cookies?.lehu_admin_session;
  clearAdminSession(res, token);
  res.redirect('/admin/login');
});

app.get('/admin', requireAdmin, async (req, res, next) => {
  try {
    const state = await readState();
    const feedbackItems = [...state.feedback].sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
    const announcementItems = [...state.announcements].sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));

    res.status(200).send(
      renderDashboard({
        state,
        feedbackItems,
        announcementItems,
        message: trimText(req.query.message ?? '')
      })
    );
  } catch (error) {
    next(error);
  }
});

app.post('/admin/version', requireAdmin, async (req, res, next) => {
  try {
    const appName = trimText(req.body.appName ?? '');
    const latestVersion = trimText(req.body.latestVersion ?? '');
    const latestBuild = Number.parseInt(String(req.body.latestBuild ?? ''), 10);
    const updateTitle = trimText(req.body.updateTitle ?? '');
    const updateMessage = trimText(req.body.updateMessage ?? '');
    const downloadUrl = trimText(req.body.downloadUrl ?? '');
    const noticeText = trimText(req.body.noticeText ?? '');
    const forceUpdate = isTruthy(req.body.forceUpdate);

    if (!latestVersion) {
      res.status(400).send('版本号不能为空。');
      return;
    }

    if (!Number.isFinite(latestBuild) || latestBuild < 1) {
      res.status(400).send('Build 号必须是正整数。');
      return;
    }

    await mutateState((state) => {
      state.meta.appName = appName || state.meta.appName;
      state.meta.latestVersion = latestVersion;
      state.meta.latestBuild = latestBuild;
      state.meta.forceUpdate = forceUpdate;
      state.meta.updateTitle = updateTitle || state.meta.updateTitle;
      state.meta.updateMessage = updateMessage || '';
      state.meta.downloadUrl = downloadUrl;
      state.meta.noticeText = noticeText;
      state.meta.publishedAt = nowIso();
    });

    res.redirect('/admin?message=' + encodeURIComponent('版本设置已保存。'));
  } catch (error) {
    next(error);
  }
});

app.post('/admin/announcements', requireAdmin, async (req, res, next) => {
  try {
    const title = trimText(req.body.title ?? '');
    const content = trimText(req.body.content ?? '');
    const active = isTruthy(req.body.active);

    if (!title || !content) {
      res.status(400).send('公告标题和内容不能为空。');
      return;
    }

    validateLength(title, 160, '标题');
    validateLength(content, 4000, '内容');

    await mutateState((state) => {
      if (active) {
        state.announcements = state.announcements.map((item) => ({
          ...item,
          active: false
        }));
      }

      state.announcements.unshift({
        id: makeId('ann'),
        title,
        content,
        active,
        createdAt: nowIso(),
        updatedAt: nowIso()
      });
    });

    res.redirect('/admin?message=' + encodeURIComponent('公告已发布。'));
  } catch (error) {
    next(error);
  }
});

app.get('/admin/feedback/:id', requireAdmin, async (req, res, next) => {
  try {
    const state = await readState();
    const item = state.feedback.find((feedback) => feedback.id === req.params.id);

    if (!item) {
      res.status(404).send('未找到反馈。');
      return;
    }

    res.status(200).send(
      renderFeedbackDetail({
        state,
        item
      })
    );
  } catch (error) {
    next(error);
  }
});

app.post('/admin/feedback/:id/reply', requireAdmin, async (req, res, next) => {
  try {
    const message = trimText(req.body.message ?? '');
    const status = trimText(req.body.status ?? '');

    if (!message) {
      res.status(400).send('回复内容不能为空。');
      return;
    }

    validateLength(message, 4000, '回复内容');

    const now = nowIso();
    const feedbackId = req.params.id;

    const updated = await mutateState((state) => {
      const item = state.feedback.find((feedback) => feedback.id === feedbackId);
      if (!item) {
        return null;
      }

      item.replies = Array.isArray(item.replies) ? item.replies : [];
      item.replies.push({
        id: makeId('rp'),
        author: 'admin',
        message,
        createdAt: now
      });
      item.status = ['open', 'closed'].includes(status) ? status : 'replied';
      item.updatedAt = now;

      return item;
    });

    if (!updated) {
      res.status(404).send('未找到反馈。');
      return;
    }

    res.redirect(`/admin/feedback/${encodeURIComponent(feedbackId)}`);
  } catch (error) {
    next(error);
  }
});

app.get('/', (req, res) => {
  res.type('text').send('Lehu update feedback server is running.');
});

app.use((req, res) => {
  if (req.path.startsWith('/api/')) {
    res.status(404).json({
      success: false,
      error: 'Not Found'
    });
    return;
  }

  res.status(404).type('text').send('Not Found');
});

app.use((error, req, res, next) => {
  const message = error instanceof Error ? error.message : 'Internal Server Error';
  console.error(error);

  if (req.path.startsWith('/api/')) {
    res.status(500).json({
      success: false,
      error: message
    });
    return;
  }

  res.status(500).type('text').send(message);
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Lehu update feedback server listening on ${port}`);
});
