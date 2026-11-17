# Inbox drain — three-state protocol

Inter-persona coordination runs on file inboxes. Each persona has `<persona-dir>/inbox/` (work
arriving) paired with `<persona-dir>/processing/` (work claimed but not finished). The two-dir
split is what makes a drain crash-safe.

```
inbox/file.md  →  processing/file.md  →  deleted (or moved to notes/)
   pending           work in flight            done
```

## The loop (every drain)

1. **Read** the inbox item.
2. **Claim** it — move to `processing/` *before* doing anything. This marks it in-flight.
3. **Decide + do** — accept and do the work, reply for clarification (write to the sender's
   inbox), or decline. This step is judgment; the helper doesn't make it for you.
4. **Finish** — delete the `processing/` copy (or move it to `notes/` to keep the record).

## Re-orient (session start / after a crash)

Check `processing/` **before** `inbox/`. Anything there is a task that was started but not
confirmed done — finish it (or restart it) before draining new items. An empty `processing/`
means "caught up"; a non-empty one is a load-bearing "not caught up" signal.

Why: without the two-dir split, a crash between "work done" and "file deleted" leaves the item
in `inbox/`, and the next drain re-does it (double-work, double-pings). Claiming into
`processing/` first makes mid-task state explicit.

## Helper

`drain.sh` does the moves safely (the judgment stays yours):

```bash
framework/inbox-drain/drain.sh status <persona-dir>          # counts + stuck items
framework/inbox-drain/drain.sh next   <persona-dir>          # oldest pending item path
framework/inbox-drain/drain.sh claim  <persona-dir> <file>   # inbox -> processing
framework/inbox-drain/drain.sh done   <persona-dir> <file>   # remove from processing
framework/inbox-drain/drain.sh keep   <persona-dir> <file>   # processing -> notes/
```

You don't have to use the helper — plain `mv`/`rm` following the protocol is equivalent. It
exists so the moves are consistent and `status` surfaces stuck items on re-orient.
