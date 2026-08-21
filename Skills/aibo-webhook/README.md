# Aibo Webhook Skill

English · [简体中文](#简体中文)

Deliver notifications from your apps and services to [Aibo](https://github.com/fenxer/agent-aibo) as desktop bubbles.

Ask your Agent to install this skill (this folder), then to wire your product’s notifications to Aibo. It will ask how you want traffic routed to your Mac (such as a managed tunnel, mesh VPN, or reverse proxy), then guide you through listener configuration, a signed smoke test, and verification. Ingress is your choice; the skill does not lock you into any vendor.

Have Aibo running. **Settings → Webhook** has the Local URL, Secret, and Tunnel URL the Agent will ask for. Never commit the Secret to git.

## Use the skill

In the repo that **sends** events, you can say:

> Install the Aibo webhook skill (https://github.com/fenxer/agent-aibo/tree/main/Skills/aibo-webhook), then set up webhooks so deploys / CI / this app notify Aibo.



## Doing it yourself

Aibo listens only on `127.0.0.1`. Expose that endpoint using whatever method you prefer — a tunnel, a Tailscale-style funnel, or a reverse proxy reaching this Mac — and set that public or VPN URL as **Tunnel URL** (path `/webhook`).

Senders `POST` JSON (`source`, `status`, `summary`) and sign the **raw body** with HMAC-SHA256 using the Shared Secret:

```http
X-Webhook-Signature: sha256=<hex>
X-Webhook-ID: <unique id>
```

If the upstream service cannot set these headers, place a small adapter in front. Payload contracts, status codes, and a test signer script are in `SKILL.md`, `references/protocol.md`, and `scripts/send-test.sh`.

---



## 简体中文

将应用与服务的通知发送至 [Aibo](https://github.com/fenxer/agent-aibo)，在桌面以气泡形式呈现。

让 Agent 安装本目录这个 skill，再让它把产品通知接到 Aibo。它会问你希望如何把流量路由到这台 Mac（托管隧道、组网 VPN 或自有反向代理），然后带你完成监听、带签名的测试和验收。入口可以自己选，skill 不绑定某一家平台。

先打开 Aibo。**设置 → Webhook** 里有 Agent 会要的 Local URL、Secret 和 Tunnel URL。Secret 记得不要进 git。

## 使用 skill

在**发送方**仓库里可以对 Agent 说：

> 安装 Aibo webhook skill，链接是 https://github.com/fenxer/agent-aibo/tree/main/Skills/aibo-webhook，然后把部署 / CI / 这个应用的通知接入 Aibo。


## 手动接入

Aibo 仅监听 `127.0.0.1`。按你习惯的方式将该地址暴露给外部即可——例如使用隧道、Tailscale 一类的 funnel 或能反向代理至这台 Mac 的服务——随后将该公网或 VPN 地址填入 **Tunnel URL**（请求路径为 `/webhook`）。

发送方以 `POST` 发送 JSON（包含 `source`、`status`、`summary`），并使用 Shared Secret 对 **原始 body** 进行 HMAC-SHA256 签名：

```http
X-Webhook-Signature: sha256=<hex>
X-Webhook-ID: <unique id>
```

若上游服务无法自定义这些请求头，可在前面加一层轻量 adapter。协议约定、状态码说明与测试签名脚本详见 `SKILL.md`、`references/protocol.md` 和 `scripts/send-test.sh`。