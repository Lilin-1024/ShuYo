function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function formatDateTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '-';
  }

  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit'
  }).format(date);
}

function shell(title, body) {
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)}</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #f4f6f8;
      --panel: #ffffff;
      --line: #d8dee6;
      --text: #1f2937;
      --muted: #6b7280;
      --accent: #2563eb;
      --input: #ffffff;
      --accent-soft: #dbeafe;
      --warn: #b45309;
      --ok: #15803d;
      --bad: #b91c1c;
      --shadow: 0 1px 2px rgba(0, 0, 0, 0.03);
      --stat-line: #e5e7eb;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0f141b;
        --panel: #171d26;
        --line: #2d3745;
        --text: #e5e7eb;
        --muted: #9ca3af;
        --accent: #7bb2ff;
        --input: #111821;
        --accent-soft: #17263d;
        --warn: #fbbf24;
        --ok: #4ade80;
        --bad: #f87171;
        --shadow: 0 1px 2px rgba(0, 0, 0, 0.22);
        --stat-line: #263241;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--text);
    }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .page {
      max-width: 1180px;
      margin: 0 auto;
      padding: 24px;
    }
    .topbar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
      margin-bottom: 20px;
    }
    .title {
      font-size: 24px;
      font-weight: 700;
      margin: 0;
    }
    .subtitle {
      color: var(--muted);
      font-size: 14px;
      margin-top: 6px;
    }
    .btn, button {
      border: 0;
      background: var(--accent);
      color: #fff;
      padding: 10px 14px;
      border-radius: 10px;
      font-size: 14px;
      cursor: pointer;
    }
    .btn.secondary {
      background: var(--accent-soft);
      color: var(--text);
    }
    .btn.danger {
      background: var(--bad);
    }
    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 16px;
      padding: 18px;
      margin-bottom: 16px;
      box-shadow: var(--shadow);
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 16px;
    }
    .grid-3 {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
    }
    label {
      display: block;
      font-size: 13px;
      color: var(--muted);
      margin-bottom: 6px;
    }
    input[type="text"],
    input[type="number"],
    input[type="password"],
    textarea,
    select {
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 10px 12px;
      font: inherit;
      background: var(--input);
      color: var(--text);
    }
    textarea {
      min-height: 120px;
      resize: vertical;
    }
    .row {
      display: flex;
      gap: 12px;
      align-items: center;
      flex-wrap: wrap;
    }
    .stats {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 0;
    }
    .stats-card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 16px;
      margin-bottom: 22px;
      overflow: hidden;
      box-shadow: var(--shadow);
    }
    .stat {
      border-right: 1px solid var(--stat-line);
      padding: 16px;
    }
    .stat:last-child {
      border-right: 0;
    }
    .stat .value {
      font-size: 24px;
      font-weight: 700;
      line-height: 1.1;
      margin-top: 8px;
    }
    .muted { color: var(--muted); }
    .table {
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
    }
    .table th, .table td {
      text-align: left;
      padding: 10px 8px;
      border-bottom: 1px solid var(--line);
      vertical-align: top;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      padding: 4px 8px;
      border-radius: 999px;
      font-size: 12px;
      background: var(--accent-soft);
      color: var(--accent);
    }
    .badge.ok { background: #dcfce7; color: var(--ok); }
    .badge.warn { background: #fef3c7; color: var(--warn); }
    .badge.bad { background: #fee2e2; color: var(--bad); }
    .split {
      display: grid;
      grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr);
      gap: 16px;
    }
    .item-list {
      display: grid;
      gap: 12px;
    }
    .item {
      padding: 12px 0;
      border-bottom: 1px solid var(--line);
    }
    .item:last-child { border-bottom: 0; }
    .small {
      font-size: 12px;
      color: var(--muted);
    }
    .notice {
      background: var(--accent-soft);
      border: 1px solid var(--line);
      padding: 12px 14px;
      border-radius: 12px;
      margin-bottom: 16px;
    }
    .error {
      background: rgba(185, 28, 28, 0.1);
      border: 1px solid rgba(185, 28, 28, 0.24);
      color: var(--bad);
      padding: 12px 14px;
      border-radius: 12px;
      margin-bottom: 16px;
    }
    @media (max-width: 900px) {
      .grid, .grid-3, .stats, .split {
        grid-template-columns: 1fr;
      }
      .stat {
        border-right: 0;
        border-bottom: 1px solid var(--stat-line);
      }
      .stat:last-child {
        border-bottom: 0;
      }
      .page { padding: 16px; }
    }
  </style>
</head>
<body>
  <div class="page">
    ${body}
  </div>
</body>
</html>`;
}

function renderLoginPage({ errorMessage = '' } = {}) {
  const error = errorMessage
    ? `<div class="error">${escapeHtml(errorMessage)}</div>`
    : '';

  return shell(
    '管理员登录',
    `<div class="card" style="max-width: 480px; margin: 72px auto 0;">
      <h1 class="title">管理员登录</h1>
      <p class="subtitle">用于管理版本、公告和反馈回复。</p>
      ${error}
      <form method="post" action="/admin/login">
        <label for="password">管理员密码</label>
        <input id="password" name="password" type="password" autocomplete="current-password" required />
        <div style="margin-top: 16px;">
          <button type="submit">登录</button>
        </div>
      </form>
    </div>`
  );
}

function renderDashboard({ state, feedbackItems, announcementItems, message = '' }) {
  const meta = state.meta;
  const notice = message ? `<div class="notice">${escapeHtml(message)}</div>` : '';
  const openCount = feedbackItems.filter((item) => item.status === 'open').length;
  const repliedCount = feedbackItems.filter((item) => item.status === 'replied').length;
  const closedCount = feedbackItems.filter((item) => item.status === 'closed').length;
  const latestFeedback = feedbackItems.slice(0, 12);
  const latestAnnouncements = announcementItems.slice(0, 8);

  return shell(
    'Lehu 后台',
    `<div class="topbar">
      <div>
        <h1 class="title">${escapeHtml(meta.appName)} 后台</h1>
        <div class="subtitle">版本检查、公告、反馈与回复都在这里处理。</div>
      </div>
      <div class="row">
        <a class="btn secondary" href="/admin/logout">退出登录</a>
      </div>
    </div>
    ${notice}
    <div class="stats-card">
      <div class="stats">
        <div class="stat"><div class="muted">总反馈</div><div class="value">${feedbackItems.length}</div></div>
        <div class="stat"><div class="muted">待处理</div><div class="value">${openCount}</div></div>
        <div class="stat"><div class="muted">已回复</div><div class="value">${repliedCount}</div></div>
        <div class="stat"><div class="muted">已关闭</div><div class="value">${closedCount}</div></div>
      </div>
    </div>

    <div class="card">
      <h2 class="title" style="font-size: 20px;">版本设置</h2>
      <p class="subtitle">客户端启动时会读取这里的内容。</p>
      <form method="post" action="/admin/version">
        <div class="grid">
          <div>
            <label for="appName">应用名称</label>
            <input id="appName" name="appName" type="text" value="${escapeHtml(meta.appName)}" />
          </div>
          <div>
            <label for="downloadUrl">下载地址</label>
            <input id="downloadUrl" name="downloadUrl" type="text" value="${escapeHtml(meta.downloadUrl)}" placeholder="https://..." />
          </div>
          <div>
            <label for="latestVersion">最新版本号</label>
            <input id="latestVersion" name="latestVersion" type="text" value="${escapeHtml(meta.latestVersion)}" />
          </div>
          <div>
            <label for="latestBuild">Build 号</label>
            <input id="latestBuild" name="latestBuild" type="number" min="1" step="1" value="${escapeHtml(meta.latestBuild)}" />
          </div>
          <div>
            <label for="updateTitle">更新标题</label>
            <input id="updateTitle" name="updateTitle" type="text" value="${escapeHtml(meta.updateTitle)}" />
          </div>
          <div>
            <label for="forceUpdate">强制更新</label>
            <select id="forceUpdate" name="forceUpdate">
              <option value="false"${meta.forceUpdate ? '' : ' selected'}>否</option>
              <option value="true"${meta.forceUpdate ? ' selected' : ''}>是</option>
            </select>
          </div>
        </div>
        <div style="margin-top: 12px;">
          <label for="updateMessage">更新说明</label>
          <textarea id="updateMessage" name="updateMessage">${escapeHtml(meta.updateMessage)}</textarea>
        </div>
        <div style="margin-top: 12px;">
          <label for="noticeText">弹窗通告</label>
          <textarea id="noticeText" name="noticeText">${escapeHtml(meta.noticeText)}</textarea>
        </div>
        <div style="margin-top: 16px;">
          <button type="submit">保存版本设置</button>
        </div>
      </form>
    </div>

    <div class="split">
      <div class="card">
        <h2 class="title" style="font-size: 20px;">最近反馈</h2>
        <p class="subtitle">点击标题进入单条详情和回复页。</p>
        <div class="item-list">
          ${
            latestFeedback.length
              ? latestFeedback
                  .map(
                    (item) => `
                <div class="item">
                  <div class="row" style="justify-content: space-between; align-items: start;">
                    <div>
                      <div style="font-weight: 600;">
                        <a href="/admin/feedback/${encodeURIComponent(item.id)}">${escapeHtml(item.title || '未命名反馈')}</a>
                      </div>
                      <div class="small">${escapeHtml(item.content.slice(0, 120))}${item.content.length > 120 ? '...' : ''}</div>
                      <div class="small" style="margin-top: 6px;">${escapeHtml(formatDateTime(item.createdAt))} · ${escapeHtml(item.appVersion || '-')}</div>
                    </div>
                    <span class="badge ${item.status === 'open' ? 'warn' : item.status === 'closed' ? 'bad' : 'ok'}">${escapeHtml(item.status)}</span>
                  </div>
                </div>`
                  )
                  .join('')
              : '<div class="small">暂无反馈。</div>'
          }
        </div>
      </div>

      <div class="card">
        <h2 class="title" style="font-size: 20px;">公告</h2>
        <p class="subtitle">最近创建的公告会优先显示。</p>
        <form method="post" action="/admin/announcements">
          <label for="announcementTitle">公告标题</label>
          <input id="announcementTitle" name="title" type="text" required />
          <div style="margin-top: 12px;">
            <label for="announcementContent">公告内容</label>
            <textarea id="announcementContent" name="content" required></textarea>
          </div>
          <div class="row" style="margin-top: 12px;">
            <label style="margin: 0; display: flex; align-items: center; gap: 8px;">
              <input type="checkbox" name="active" checked />
              启用
            </label>
          </div>
          <div style="margin-top: 12px;">
            <button type="submit">发布公告</button>
          </div>
        </form>
        <div style="margin-top: 18px;">
          ${
            latestAnnouncements.length
              ? latestAnnouncements
                  .map(
                    (item) => `
                <div class="item">
                  <div style="font-weight: 600;">${escapeHtml(item.title)}</div>
                  <div class="small" style="margin-top: 4px;">${escapeHtml(item.content.slice(0, 140))}${item.content.length > 140 ? '...' : ''}</div>
                  <div class="small" style="margin-top: 4px;">${escapeHtml(formatDateTime(item.createdAt))}</div>
                </div>`
                  )
                  .join('')
              : '<div class="small">暂无公告。</div>'
          }
        </div>
      </div>
    </div>`
  );
}

function renderFeedbackDetail({ state, item, message = '' }) {
  const notice = message ? `<div class="notice">${escapeHtml(message)}</div>` : '';
  const replies = Array.isArray(item.replies) ? item.replies : [];

  return shell(
    `反馈 ${item.id}`,
    `<div class="topbar">
      <div>
        <h1 class="title">反馈详情</h1>
        <div class="subtitle"><a href="/admin">返回后台</a> · ${escapeHtml(item.id)}</div>
      </div>
      <div class="row">
        <span class="badge ${item.status === 'open' ? 'warn' : item.status === 'closed' ? 'bad' : 'ok'}">${escapeHtml(item.status)}</span>
      </div>
    </div>
    ${notice}
    <div class="card">
      <div class="grid">
        <div>
          <div class="small">标题</div>
          <div style="font-size: 18px; font-weight: 700; margin-top: 6px;">${escapeHtml(item.title || '未命名反馈')}</div>
        </div>
        <div>
          <div class="small">提交时间</div>
          <div style="margin-top: 6px;">${escapeHtml(formatDateTime(item.createdAt))}</div>
        </div>
        <div>
          <div class="small">客户端版本</div>
          <div style="margin-top: 6px;">${escapeHtml(item.appVersion || '-')}</div>
        </div>
        <div>
          <div class="small">联系方式</div>
          <div style="margin-top: 6px;">${escapeHtml(item.contact || '-')}</div>
        </div>
      </div>
      <div style="margin-top: 16px;">
        <div class="small">内容</div>
        <div style="margin-top: 6px; white-space: pre-wrap; line-height: 1.6;">${escapeHtml(item.content)}</div>
      </div>
    </div>

    <div class="split">
      <div class="card">
        <h2 class="title" style="font-size: 20px;">回复</h2>
        ${
          replies.length
            ? replies
                .map(
                  (reply) => `
              <div class="item">
                <div class="small">${escapeHtml(formatDateTime(reply.createdAt))} · ${escapeHtml(reply.author || 'admin')}</div>
                <div style="margin-top: 6px; white-space: pre-wrap; line-height: 1.6;">${escapeHtml(reply.message)}</div>
              </div>`
                )
                .join('')
            : '<div class="small" style="margin-top: 10px;">暂无回复。</div>'
        }
      </div>

      <div class="card">
        <h2 class="title" style="font-size: 20px;">新增回复</h2>
        <form method="post" action="/admin/feedback/${encodeURIComponent(item.id)}/reply">
          <div>
            <label for="replyMessage">回复内容</label>
            <textarea id="replyMessage" name="message" required></textarea>
          </div>
          <div style="margin-top: 12px;">
            <label for="status">状态</label>
            <select id="status" name="status">
              <option value="auto"${item.status === 'closed' ? '' : ' selected'}>回复后设为已回复</option>
              <option value="open">保持待处理</option>
              <option value="closed"${item.status === 'closed' ? ' selected' : ''}>关闭</option>
            </select>
          </div>
          <div style="margin-top: 12px;">
            <button type="submit">保存回复</button>
          </div>
        </form>
      </div>
    </div>`
  );
}

export {
  escapeHtml,
  formatDateTime,
  renderDashboard,
  renderFeedbackDetail,
  renderLoginPage,
  shell
};
