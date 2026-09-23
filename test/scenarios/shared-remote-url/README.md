# Scenario: shared-remote-url

Two subtree remotes with different names but the same URL -- the same
upstream repo checked out into two directories.

- **Monorepo**: remotes `vendor/a` and `vendor/b` both point at the same
  bare repo; both directories were added at `seed`, no local changes since.
- **Remote**: one commit (`seed`).

Each remote has its own tracking refs, so the tool treats the two
directories like two clones of one repo, each pushing to and pulling from
the same branch:

- A push from `vendor/a` shows up as `pull` for `vendor/b` after the next
  fetch, and `git subtrees pull` brings it into `vendor/b`.
- If both directories changed, the first push wins. The second is rejected
  as non-fast-forward by the remote, just like a push from a stale clone;
  nothing gets overwritten. Pull it, then push again.

Expected `classify_subtree` result for both: `up-to-date`.

Built by `scenario_shared_remote_url` in `setup.bash`.
