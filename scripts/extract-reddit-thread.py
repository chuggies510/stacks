# extract-reddit-thread.py
# Fetch a Reddit thread (post + comments) via the public .json endpoint and emit
# a clean, score-sorted JSON structure. Output is consumed by the extract-reddit
# skill's filtering pass.
#
# Usage: python3 extract-reddit-thread.py <reddit-thread-url>
#
# Drops [removed]/[deleted] comments, sorts by score, caps to top 100 at
# depth ≤ 6. Output goes to stdout (compact JSON). Errors go to stderr.
#
# Why urllib + browser UA: bare curl is blocked by Reddit's edge. Reddit's
# .json endpoint serves the same data old.reddit.com renders, no auth needed,
# no rate limit at one-shot scale. PRAW is the upgrade if you hit limits.

import json
import re
import sys
import urllib.request
import urllib.error

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
      "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15")

MAX_COMMENTS = 100
MAX_DEPTH = 6


def die(msg, code=1):
    sys.stderr.write(f"extract-reddit-thread: {msg}\n")
    sys.exit(code)


def normalize_url(url):
    # Accept old.reddit.com, www.reddit.com, redd.it short links, with or without
    # trailing slug. Always rewrite to the canonical /comments/{id}/.json form.
    m = re.search(r"reddit\.com/r/[^/]+/comments/([a-z0-9]+)", url)
    if not m:
        m = re.search(r"redd\.it/([a-z0-9]+)", url)
    if not m:
        die(f"could not extract post id from url: {url}")
    return f"https://www.reddit.com/comments/{m.group(1)}/.json?limit=500&raw_json=1"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 429:
            die("Reddit returned 429 (rate limited). Wait a few minutes or switch to PRAW with API creds.", 2)
        if e.code == 403:
            die("Reddit returned 403 (blocked). Try again from a residential IP, or switch to PRAW.", 3)
        die(f"HTTP {e.code} fetching {url}")
    except urllib.error.URLError as e:
        die(f"network error: {e.reason}")


def walk_comments(children, depth, out):
    # Recurse past deleted/removed parents — moderator-deleted parents with live
    # children do happen on Reddit, and the children may carry the substance.
    for c in children:
        if c.get("kind") != "t1":
            continue
        d = c.get("data", {})
        body = d.get("body", "")
        replies = d.get("replies")
        if body and body not in ("[removed]", "[deleted]"):
            out.append({
                "author": d.get("author") or "[deleted]",
                "score": d.get("score", 0),
                "depth": depth,
                "body": body,
            })
        if isinstance(replies, dict) and depth < MAX_DEPTH:
            walk_comments(replies["data"]["children"], depth + 1, out)


def main():
    if len(sys.argv) < 2:
        die("usage: extract-reddit-thread.py <url>")
    url = sys.argv[1]
    raw = fetch(normalize_url(url))
    # Private/quarantined subreddits return a dict with an error message instead
    # of the [post, comments] list shape — defend against that here.
    if not isinstance(raw, list) or len(raw) < 2:
        die("unexpected response shape (private/quarantined subreddit?)")

    post = raw[0]["data"]["children"][0]["data"]
    comments_root = raw[1]["data"]["children"]

    flat = []
    walk_comments(comments_root, 0, flat)
    flat.sort(key=lambda c: c["score"], reverse=True)

    out = {
        "source_url": url,
        "permalink": "https://www.reddit.com" + post.get("permalink", ""),
        "title": post.get("title", ""),
        "author": post.get("author", ""),
        "subreddit": post.get("subreddit", ""),
        "selftext": post.get("selftext", ""),
        "linked_url": post.get("url_overridden_by_dest") or post.get("url", ""),
        "score": post.get("score", 0),
        "upvote_ratio": post.get("upvote_ratio"),
        "num_comments_total": post.get("num_comments", 0),
        "created_utc": post.get("created_utc"),
        "stats": {
            "comments_parsed": len(flat),
            "comments_kept": min(len(flat), MAX_COMMENTS),
            "max_depth_applied": MAX_DEPTH,
        },
        "comments": flat[:MAX_COMMENTS],
    }
    sys.stdout.write(json.dumps(out, ensure_ascii=False))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
