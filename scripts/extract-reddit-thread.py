# extract-reddit-thread.py
# Fetch a Reddit thread (post + comments) via the public .json endpoint and emit
# a clean, score-sorted JSON structure. Output is consumed by the extract-reddit
# skill's filtering pass.
#
# Usage:
#   python3 extract-reddit-thread.py <reddit-thread-url> [--max-comments N] [--max-depth D]
#
# Defaults: --max-comments 100, --max-depth 6. Comments past these caps are
# dropped. Comments with body in {"[removed]", "[deleted]"} are dropped before
# capping. Output goes to stdout. Errors go to stderr with exit code 1.
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


def parse_args(argv):
    if len(argv) < 2:
        die("usage: extract-reddit-thread.py <url> [--max-comments N] [--max-depth D]")
    url = argv[1]
    max_comments = 100
    max_depth = 6
    i = 2
    while i < len(argv):
        a = argv[i]
        if a == "--max-comments" and i + 1 < len(argv):
            max_comments = int(argv[i + 1]); i += 2
        elif a == "--max-depth" and i + 1 < len(argv):
            max_depth = int(argv[i + 1]); i += 2
        else:
            die(f"unknown arg: {a}")
    return url, max_comments, max_depth


def die(msg, code=1):
    sys.stderr.write(f"extract-reddit-thread: {msg}\n")
    sys.exit(code)


def normalize_url(url):
    # Accept old.reddit.com, www.reddit.com, redd.it short links, with or without
    # trailing slug. Always rewrite to www.reddit.com/comments/{id}/.json so the
    # endpoint resolves the same way regardless of input form.
    m = re.search(r"reddit\.com/r/[^/]+/comments/([a-z0-9]+)", url)
    if not m:
        m = re.search(r"redd\.it/([a-z0-9]+)", url)
    if not m:
        die(f"could not extract post id from url: {url}")
    post_id = m.group(1)
    return f"https://www.reddit.com/comments/{post_id}/.json?limit=500&raw_json=1"


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


def walk_comments(children, depth, parent_id, max_depth, out):
    for c in children:
        if c.get("kind") != "t1":
            continue
        d = c.get("data", {})
        body = d.get("body", "")
        if body in ("[removed]", "[deleted]") or not body:
            # still recurse — a deleted parent may have substantive children
            replies = d.get("replies")
            if isinstance(replies, dict) and depth < max_depth:
                walk_comments(replies["data"]["children"], depth + 1, d.get("id"), max_depth, out)
            continue
        out.append({
            "id": d.get("id"),
            "parent": parent_id,
            "author": d.get("author") or "[deleted]",
            "score": d.get("score", 0),
            "depth": depth,
            "created_utc": d.get("created_utc"),
            "body": body,
        })
        replies = d.get("replies")
        if isinstance(replies, dict) and depth < max_depth:
            walk_comments(replies["data"]["children"], depth + 1, d.get("id"), max_depth, out)


def main():
    url, max_comments, max_depth = parse_args(sys.argv)
    api_url = normalize_url(url)
    raw = fetch(api_url)
    if not isinstance(raw, list) or len(raw) < 2:
        die("unexpected response shape from reddit")

    post = raw[0]["data"]["children"][0]["data"]
    comments_root = raw[1]["data"]["children"]

    flat = []
    walk_comments(comments_root, 0, None, max_depth, flat)
    flat.sort(key=lambda c: c["score"], reverse=True)
    capped = flat[:max_comments]

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
            "comments_kept": len(capped),
            "max_depth_applied": max_depth,
            "max_comments_applied": max_comments,
            "dropped_deleted_or_removed": post.get("num_comments", 0) - len(flat),
        },
        "comments": capped,
    }
    sys.stdout.write(json.dumps(out, indent=2, ensure_ascii=False))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
