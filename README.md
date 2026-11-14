# fpprobe

**代理出口指纹检测靶机。** 打开网页就能看到"网站眼里的你"：TCP SYN 指纹（p0f）、TLS ClientHello（JA4）、HTTP 头、TCP 握手 RTT 与浏览器测到的应用层 RTT，并判断这些信息是否一致。

> English summary: fpprobe is a self-hosted fingerprint test target. It passively captures each visitor's TCP handshake (p0f signature), terminates TLS itself to compute JA4, measures application-layer RTT from the page, and reports whether the TCP-level OS matches the browser's claimed OS and whether the timing looks proxied. Single static binary or a multi-arch Docker image.

适合用来：

- 检查代理 / VPN 出口会不会暴露"TCP 层是 Linux、浏览器说自己是 Windows"之类的不一致
- 给出口指纹伪装工具（例如 [ssfp](https://github.com/aidever/ssfp)）校准模板：设备直连访问一次，拿到真机的 SYN 字段
- 收集 JA4 与系统的对应关系

## 能看到什么

| 层 | 内容 |
|---|---|
| TCP | 初始 TTL、窗口、窗口缩放、MSS、选项顺序、时间戳、p0f 签名与系统判定、SYN 重传 |
| TLS | JA4 / JA4_r、TLS 版本、SNI、ALPN、套件和扩展数量 |
| HTTP | User-Agent、`Sec-CH-UA-Platform`、Accept-Language 等 |
| 时序 | 抓包测到的 TCP 握手 RTT、内核 `tcp_info` RTT、ACK 到首包的间隔、页面 JS 测到的应用层 RTT |
| 判定 | TCP 层系统与浏览器自报系统是否一致；握手 RTT 与应用层 RTT 差距是否像经过代理 |

每次访问追加一行到 JSONL 日志。页面上的"历史"只显示同一来源 IP 的记录。命令行访问（`curl http://靶机:8080/`）直接返回 JSON 报告。

## 工作方式

- 用 `AF_PACKET` + cBPF 被动抓靶机端口上的 TCP 包，不改动内核协议栈，内核照常完成握手
- 自己终结 TLS（rustls），从原始字节解析 ClientHello 计算 JA4
- 用 [huginn-net](https://github.com/biandratti/huginn-net) 的 p0f 库匹配 SYN 签名
- 页面 JS 反复请求 `/ping` 测应用层 RTT，再把结果和客户端信息回报给服务端

## 快速开始（Docker）

镜像：`ghcr.io/aidever/fpprobe`（linux/amd64、linux/arm64）。

需要 **host 网络**（抓的是宿主网卡上的包）和 **`NET_RAW`** 能力：

```sh
docker run -d --name fpprobe --restart unless-stopped \
  --network host --cap-add NET_RAW \
  -v fpprobe-data:/var/lib/fpprobe \
  -v /etc/letsencrypt:/certs:ro \
  ghcr.io/aidever/fpprobe:latest \
  --iface eth0 --http-port 8080 --tls-port 8443 \
  --cert /certs/live/fp.example.com/fullchain.pem \
  --key  /certs/live/fp.example.com/privkey.pem
```

docker compose：

```yaml
services:
  fpprobe:
    image: ghcr.io/aidever/fpprobe:latest
    network_mode: host
    cap_add: [NET_RAW]
    restart: unless-stopped
    volumes:
      - fpprobe-data:/var/lib/fpprobe
      - /etc/letsencrypt:/certs:ro
    command: >
      --iface eth0 --http-port 8080 --tls-port 8443
      --cert /certs/live/fp.example.com/fullchain.pem
      --key /certs/live/fp.example.com/privkey.pem
volumes:
  fpprobe-data:
```

然后浏览器打开 `https://fp.example.com:8443/`。不给证书时只开 HTTP（没有 JA4，其余照常）。

## 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `--iface` | `eth0` | 抓包网卡，即访客流量进来的网卡 |
| `--bind` | `0.0.0.0` | 监听地址 |
| `--http-port` | `8080` | HTTP 端口 |
| `--tls-port` | `8443` | HTTPS 端口（给了证书才开） |
| `--cert` / `--key` | 无 | PEM 证书链与私钥。每 10 分钟检查一次，文件变了就重载，可配合 certbot / Caddy 续期 |
| `--log` | `/var/lib/fpprobe/visits.jsonl` | 访问日志（JSONL）。启动时读回最近 500 条 |

**注意：**

- 靶机必须**直接**接收访客的 TCP 连接，前面不能有 CDN 或反向代理（如 Nginx、Caddy），否则抓到的是代理的 SYN。
- 证书可以由同机的 Caddy / certbot 申请，fpprobe 只读取文件。

## 从源码构建

```sh
cargo build --release      # target/release/fpprobe
# 静态二进制
rustup target add x86_64-unknown-linux-musl
cargo build --release --target x86_64-unknown-linux-musl
```

运行需要 root 或 `CAP_NET_RAW`：

```sh
sudo setcap cap_net_raw+ep target/release/fpprobe
```

镜像构建：`docker build -t fpprobe .`。推到 `main` 时 GitHub Actions 发布 `latest`，打 `v*` 标签时发布对应版本号。

## 隐私

靶机会记录访客 IP、UA、指纹和时序。公开部署时请告知访问者，并按需清理日志。

## 许可证

MIT，见 [LICENSE](LICENSE)。
