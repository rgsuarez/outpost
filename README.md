# Outpost

**Multi-Agent Headless Executor System v2.0.0**

Outpost enables Claude sessions to dispatch coding tasks to remote AI agents. Five agents run in parallel on dedicated infrastructure.

## Quick Start

**HTTP API:** `http://outpost-control-plane-dev-140603164.us-east-1.elb.amazonaws.com`
**Authentication:** API Key via `X-API-Key` header
**Documentation:** [OUTPOST_INTERFACE.md](OUTPOST_INTERFACE.md)

## Fleet

| Agent | Model | Cost |
|-------|-------|------|
| Claude Code | claude-opus-4-5-20251101 | $100/mo |
| OpenAI Codex | gpt-5.2-codex | $20/mo |
| Gemini CLI | gemini-3-pro-preview | $50/mo |
| Aider | deepseek/deepseek-coder | ~$0.14/MTok |
| Grok | grok-4.1 (xAI) | API |

## Architecture (v2.0)

```
HTTP Client → ALB → ECS Control Plane → ECS Fargate Workers
                         |                      |
                         v                      +-> Claude Code
                    DynamoDB                    +-> OpenAI Codex
                    CloudWatch                  +-> Gemini CLI
                    Secrets Manager             +-> Aider
                    S3 Artifacts                +-> Grok
                                                      |
                                                      +-> Isolated workspace (EFS)
```

## Features (v2.0)

- **HTTP API:** Simple REST API with JSON (no AWS credentials required)
- **Multi-Tenant:** Complete tenant isolation with per-tenant API keys
- **Model Selection:** Choose flagship/balanced/fast tiers per agent
- **Auto-Scaling:** ECS Fargate scales workers on demand
- **Observability:** CloudWatch logs and metrics for all tasks
- **Production Ready:** 97% validation pass rate (36/37 tests)

## Documentation

| File | Purpose |
|------|---------|
| [INVOKE.md](INVOKE.md) | **Landing file - copy-paste commands** |
| [OUTPOST_INTERFACE.md](OUTPOST_INTERFACE.md) | Full API specification |
| [docs/MULTI_AGENT_INTEGRATION.md](docs/MULTI_AGENT_INTEGRATION.md) | Integration guide |
| [docs/SSM_AND_PRIVILEGE_CONFIGURATION.md](docs/SSM_AND_PRIVILEGE_CONFIGURATION.md) | SSM keepalive & privilege drop setup |

## Server

- **Host:** outpost-prod (34.195.223.189)
- **SSM Instance:** mi-0bbd8fed3f0650ddb
- **Region:** us-east-1
- **Profile:** soc

---

*Outpost v1.8.0 - Multi-Agent Headless Executor*
