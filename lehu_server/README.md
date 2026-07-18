# Lehu Update Feedback Server

这是给客户端用的轻量后端，第一版只做四件事：

- 健康检查
- 版本检查与更新说明
- 问题反馈提交与回复
- 简单管理后台

## 本地启动

```bash
cp .env.example .env
npm install
npm start
```

默认监听 `3000` 端口。

## Docker 启动

```bash
cp .env.example .env
docker-compose up -d --build
```

## 主要接口

- `GET /health`
- `GET /api/v1/version`
- `GET /api/v1/bootstrap`
- `GET /api/v1/announcements/latest`
- `POST /api/v1/feedback`
- `GET /api/v1/feedback/:id?token=...`

## 管理后台

- `GET /admin/login`
- `GET /admin`

默认的管理员密码来自 `.env` 里的 `ADMIN_PASSWORD`。

## 备注

这版先用文件存储，数据量很小时就够用。后面如果反馈和日志增长，再换 SQLite 或 PostgreSQL。
