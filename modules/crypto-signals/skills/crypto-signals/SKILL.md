---
name: crypto-signals
description: Curate a ranked crypto alpha-signal digest — what's trending, what's moving, and why, with a thesis and tier per signal. Use when the operator asks for a crypto digest, "what's moving / hot / trending in crypto," a market pulse, or sets a recurring crypto brief. Read-only — surfaces ideas, never trades.
---

# Crypto signal digest

You produce a **ranked digest of crypto signals** — what's worth attention right
now and why. Read-only: you surface ideas, you don't trade. Hand a specific name to
the `crypto-research` skill for a deep-dive, and to a trading module to act.

Sources (all free unless noted):
- **CoinGecko** — trending, market movers, global regime (free; if
  `COINGECKO_API_KEY` is set, use `pro-api.coingecko.com` + `x-cg-pro-api-key`).
- **Web search** — the "why" behind each move: news, narrative, catalysts.
- The operator's own feeds (X / Reddit / onchain MCP tools) if present — fold them
  in when available, never assume them.

## Gather (CoinGecko free API: https://api.coingecko.com/api/v3)

```sh
# market regime
curl -s "https://api.coingecko.com/api/v3/global" \
 | jq '{btc_dom: .data.market_cap_percentage.btc, mcap_24h: .data.market_cap_change_percentage_24h_usd}'
# trending (what people are searching)
curl -s "https://api.coingecko.com/api/v3/search/trending" | jq '.coins[].item.symbol'
# movers — pull a wide page, then sort by 24h % for top gainers/losers
curl -s "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=100&page=1&price_change_percentage=24h,7d" \
 | jq 'sort_by(.price_change_percentage_24h) | {losers: [.[:5][] | {s:.symbol,p:.price_change_percentage_24h}], gainers: [.[-5:][] | {s:.symbol,p:.price_change_percentage_24h}]}'
```

Filter noise: ignore micro-caps with no liquidity unless there's a real catalyst;
weight moves that are corroborated by news or volume, not just price.

## For each candidate signal

1. Note the move (trending / gainer / loser / unusual volume) with the number + when.
2. Web-search the **why** — is there a real catalyst (listing, upgrade, unlock,
   partnership, exploit, macro) or is it just price? Date it.
3. Assign a tier and a one-line thesis.

## Output — the digest

```
Crypto signals — <date/time UTC>
Regime: BTC dom X% · total mcap 24h Y% · <risk-on / risk-off / chop>

A-tier (catalyst + move aligned)
- <SYM> +X% 24h — <one-line why> — <source>
B-tier (moving, thesis mixed/early)
- <SYM> … 
Watch (notable but unconfirmed / thin)
- <SYM> …

Themes: <1–2 cross-cutting narratives, e.g. "L2 rotation", "AI tokens bid">
Next: <which 1–2 names deserve a crypto-research deep-dive>
```

Keep it tight — a scannable brief, not an essay. 5–10 signals max; quality over volume.

## Recurring use

This pairs with **/loop** for a standing brief. In the persona's session:

```
/loop 4h run a crypto-signals digest and post it
```

Tune the interval to the operator (hourly for active, daily for a morning read).
Don't loop so tight it's noise — a good digest is a signal, not a tick stream.

## Discipline

- **Read-only.** Surface and rank; never place a trade from this skill.
- **The "why" is the point.** A price move with no explanation is a lead, not a
  signal — say so, don't dress it up.
- **Date everything; cite or qualify.** Stamp data with pull time; source each "why"
  or mark it unverified.
- **No predictions / no financial advice.** Rank attention and risk, not promises.
