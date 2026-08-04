# 鱼鱼传话中转服务

Cloudflare Worker + D1 中转服务。服务只保存端到端加密信封，不持有任何设备私钥或消息明文。

## 部署

```bash
npx wrangler d1 create blobfish-fish-messenger
# 把返回的 database_id 写入 wrangler.toml
npx wrangler d1 execute blobfish-fish-messenger --remote --file schema.sql
npx wrangler secret put SETUP_SECRET
npx wrangler deploy
```

`SETUP_SECRET` 只用于你和朋友首次创建收件箱，防止公开地址被滥用；至少使用 16 个字符。收件箱最多暂存 100 条密文，30 天自动过期；客户端确认接收后立即删除。
