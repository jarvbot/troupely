---
name: crypto-research
description: Produce a structured crypto research report on a token or theme — market data, fundamentals, narrative, catalysts, risks, key levels, and a setup-tier verdict. Use when the operator asks to research / analyze / break down / "what's the story on" a coin, token, ticker, contract address, or a crypto sector/theme. Read-only — it never trades or touches funds.
---

# Crypto research report

You produce a tight, sourced research report on a crypto **token** or **theme**.
Read-only: gather data, reason, write the report. Never place a trade or move funds.

Data sources (in order of preference, all free unless noted):
- **CoinGecko** — market data, fundamentals, links, categories (free API; if
  `COINGECKO_API_KEY` is set, send it as the `x-cg-pro-api-key` header for higher limits).
- **Web search** — recent news, narrative, catalysts, team/funding, controversy.
- The operator's own MCP tools if present (onchain explorers, X/news feeds) — use
  them when available, but never assume them.

## CoinGecko quick reference (free API: https://api.coingecko.com/api/v3)

Resolve a token, then pull its data. Use `curl -s`. With a Pro key set, base URL is
`https://pro-api.coingecko.com/api/v3` and add `-H "x-cg-pro-api-key: $COINGECKO_API_KEY"`.

```sh
# 1. resolve symbol/name → id
curl -s "https://api.coingecko.com/api/v3/search?query=arbitrum" | jq '.coins[0]'
# 2. full coin data (market, supply, links, categories, description)
curl -s "https://api.coingecko.com/api/v3/coins/arbitrum?localization=false&tickers=false&market_data=true&community_data=true&developer_data=false"
# 3. price history for trend/levels (e.g. 90d)
curl -s "https://api.coingecko.com/api/v3/coins/arbitrum/market_chart?vs_currency=usd&days=90"
```

For a **contract address**: `…/coins/{platform}/contract/{address}` (platform e.g.
`ethereum`, `solana`, `arbitrum-one`, `base`). For a **theme/sector**, resolve the
3–6 leading tokens and report on each plus the cross-cutting thesis.

## Report structure

Write markdown. Keep it dense and skimmable — no filler.

1. **TL;DR** — 2–3 lines: what it is, the current setup, your one-line verdict.
2. **Snapshot** — a table: price, 24h/7d/30d %, market cap (+ rank), FDV, 24h volume,
   circulating/total/max supply, ATH (+ % from ATH), chain(s).
3. **What it is** — the project in 3–5 lines: category, what problem it solves,
   how it captures value, where the token fits.
4. **Narrative & catalysts** — the live story (web search): recent news, upgrades,
   listings, partnerships, upcoming unlocks/events. Date every claim.
5. **Tokenomics & risks** — supply schedule / unlocks, holder concentration if
   findable, FDV-vs-mcap gap, sell pressure, red flags (anon team, exploit history,
   thin liquidity, regulatory). Be skeptical; call out what you couldn't verify.
6. **Structure & levels** — from the 90d history: trend, notable support/resistance,
   where price sits in range. Plain observations, not financial advice.
7. **Verdict** — a setup tier and why:
   - **A** — clean thesis + catalyst + structure aligned
   - **B** — decent thesis, mixed structure or timing
   - **C** — watch-only / thesis unproven / elevated risk
   State the key thing that would change the call.
8. **Sources** — list the URLs / endpoints you used.

## Discipline

- **Read-only.** This skill researches. It does not trade. If asked to act on the
  research, hand off to a trading capability — don't execute here.
- **Date the data.** Crypto moves fast; stamp prices and news with when you pulled them.
- **Separate fact from take.** Market data and verifiable news = facts. The thesis,
  tier, and levels = your read — label them.
- **No price predictions or financial advice.** Describe structure and risk; let the
  reader decide. Never promise returns.
- **Cite or qualify.** Every non-obvious claim gets a source or an explicit "couldn't verify."
