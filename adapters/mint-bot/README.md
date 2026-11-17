# mint-bot adapter — bring a new persona's bot online

Every persona needs its own Telegram bot (so the operator has one chat per persona, and the
plugins don't collide). `mint-bot` is the pattern for minting one without leaving your tools.

## The flow

1. **Mint** — create the bot. The portable way is Telegram's *Managed Bots* API driven through
   a manager bot you already own: the minter emits a one-tap creation link, you tap it to
   approve, and it captures the new bot's token. (The low-tech fallback is BotFather → `/newbot`
   by hand, then paste the token.)
2. **Store the token by name** in your OS secret store or gitignored `.env`, e.g.
   `TROUPELY_TG_TOKEN_<NAME>` — never in a tracked file.
3. **Add the persona** to the roster (`TROUPELY_PERSONAS` / `troupely-roster.json` / a
   `personas/<name>/` dir) and restart. The entrypoint launches its session with that token.
4. **Pair** — DM the new bot once; the channel access control gates the first message, so
   approve the operator's chat once and it's open.

## Token hygiene

- The token is the bot. Treat it like a password: secret store or `.env`, never committed.
- **Never run a second poller against a live bot's token** — two pollers on one token fight over
  `getUpdates` and drop messages. One session per bot token.
- Rotating a token (BotFather → revoke) instantly kills the old one — update the secret + restart.

## Why a minter at all

Once you're running several personas, minting by hand through BotFather every time is friction.
A minter script (driving the Managed Bots API through your manager bot, writing the token
straight to your secret store) makes "add a persona" a one-tap operation. The script itself is
small and instance-specific — it depends on your manager-bot identity and your secret store —
so troupely ships the *pattern* here rather than a binary; build the thin minter against your
own manager bot + store.
