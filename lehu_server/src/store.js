import crypto from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';

const dataDir = process.env.DATA_DIR ?? path.resolve(process.cwd(), 'data');
const dbPath = path.join(dataDir, 'db.json');

function nowIso() {
  return new Date().toISOString();
}

function toInt(value, fallback) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function defaultMeta() {
  const now = nowIso();
  return {
    appName: process.env.APP_NAME ?? 'Lehu',
    latestVersion: process.env.DEFAULT_VERSION ?? '0.1.0',
    latestBuild: toInt(process.env.DEFAULT_BUILD, 1),
    forceUpdate: false,
    updateTitle: process.env.DEFAULT_UPDATE_TITLE ?? '发现新版本',
    updateMessage: process.env.DEFAULT_UPDATE_MESSAGE ?? '欢迎使用 Lehu 客户端。',
    downloadUrl: process.env.DEFAULT_DOWNLOAD_URL ?? '',
    noticeText: process.env.DEFAULT_NOTICE_TEXT ?? '',
    publishedAt: now,
    updatedAt: now
  };
}

function defaultState() {
  return {
    meta: defaultMeta(),
    announcements: [],
    feedback: []
  };
}

function normalizeState(raw) {
  const defaults = defaultState();
  const meta = {
    ...defaults.meta,
    ...(raw?.meta ?? {})
  };

  meta.latestBuild = toInt(meta.latestBuild, defaults.meta.latestBuild);
  meta.forceUpdate = Boolean(meta.forceUpdate);
  meta.appName = String(meta.appName ?? defaults.meta.appName);
  meta.updateTitle = String(meta.updateTitle ?? defaults.meta.updateTitle);
  meta.updateMessage = String(meta.updateMessage ?? defaults.meta.updateMessage);
  meta.downloadUrl = String(meta.downloadUrl ?? defaults.meta.downloadUrl);
  meta.noticeText = String(meta.noticeText ?? defaults.meta.noticeText);
  meta.publishedAt = meta.publishedAt ?? defaults.meta.publishedAt;
  meta.updatedAt = meta.updatedAt ?? defaults.meta.updatedAt;

  const announcements = Array.isArray(raw?.announcements) ? raw.announcements : [];
  const feedback = Array.isArray(raw?.feedback) ? raw.feedback : [];

  return { meta, announcements, feedback };
}

async function ensureStorage() {
  await mkdir(dataDir, { recursive: true });

  try {
    await readFile(dbPath, 'utf8');
  } catch {
    await saveState(defaultState());
  }
}

async function readState() {
  await ensureStorage();
  try {
    const raw = await readFile(dbPath, 'utf8');
    if (!raw.trim()) {
      return defaultState();
    }
    return normalizeState(JSON.parse(raw));
  } catch {
    const defaults = defaultState();
    await saveState(defaults);
    return defaults;
  }
}

async function saveState(state) {
  await mkdir(dataDir, { recursive: true });
  const normalized = normalizeState(state);
  normalized.meta.updatedAt = nowIso();

  const tmpPath = `${dbPath}.${crypto.randomUUID()}.tmp`;
  await writeFile(tmpPath, `${JSON.stringify(normalized, null, 2)}\n`, 'utf8');
  await rename(tmpPath, dbPath);
  return normalized;
}

async function mutateState(mutator) {
  const state = await readState();
  const result = await mutator(state);
  await saveState(state);
  return result;
}

function makeId(prefix) {
  return `${prefix}_${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`;
}

function hashToken(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

export {
  dataDir,
  dbPath,
  ensureStorage,
  readState,
  saveState,
  mutateState,
  makeId,
  hashToken,
  nowIso,
  toInt
};
