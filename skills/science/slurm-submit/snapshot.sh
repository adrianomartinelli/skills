#!/usr/bin/env bash
# Create an immutable code snapshot for a batch submission, and print its path.
#
#   snapshot=$(bash <slurm-submit skill dir>/snapshot.sh <name>)   # from the project root
#   sbatch --chdir="$snapshot" \
#     --output="$snapshot/.logs/<name>/%j-%x.out" --error="$snapshot/.logs/<name>/%j-%x.err" ...
#
# <name> groups the job's logs: the script or skill submitting it (e.g. `evaluate_segmentations`).
# Logs land in the live checkout's `.logs/<name>/<job-id>-<job-name>.{out,err}` (a job's own log
# file, if it writes one, goes next to them as `.log`), reached through a `.logs` symlink in the
# snapshot. They must not live inside the snapshot: snapshots are disposable once their jobs end,
# and deleting one would delete the only record of what its jobs did.
#
# Three properties this buys, each of which has failed in practice without it:
#   * the code a multi-hour job runs cannot change under it, because `git archive` extracts a
#     commit rather than linking a checkout -- there is no `.git`, so nothing can rewrite it;
#   * the *environment* cannot change under it either, because envs are addressed by the hash of
#     `pixi.lock`. A `pixi install` in the live tree that adds a dependency produces a different
#     hash and a different directory, so a running job keeps the env it started with;
#   * paths resolve the same from the snapshot as from the live tree, because relative ones are
#     rejected up front rather than silently resolving inside the snapshot.
#
# Still prefix jobs with `PYTHONPATH=$snapshot/src` (or wherever the package's source lives):
# pixi's editable install of this project inside a shared per-lock env points at whichever snapshot
# first built that env, so a later snapshot sharing the same lock but different source would
# otherwise import the wrong commit's code. PYTHONPATH takes precedence over the editable install
# path, which neutralises that regardless of which snapshot built the shared env.
set -euo pipefail

if [[ $# -ne 1 || -z "$1" || "$1" == */* ]]; then
    echo "usage: snapshot.sh <name>  (logs go to .logs/<name>/; one path segment)" >&2
    exit 2
fi
log_name=$1

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"
repo=$(basename "$repo_root")

# A snapshot of HEAD is only meaningful if HEAD is what you are looking at. Uncommitted work is
# not in the commit, so the job would run something nobody reviewed.
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "Working tree has uncommitted changes; commit them before submitting." >&2
    echo "A snapshot extracts a commit, so those changes would NOT be in the job." >&2
    exit 1
fi

sha=$(git rev-parse HEAD)
# Project-relative default, not $HOME: home directories commonly carry a small quota on shared
# clusters, and snapshots/environments can run into the GBs. Override with SNAPSHOT_ROOT if a
# project needs somewhere else (e.g. a configured scratch root).
snapshot="${SNAPSHOT_ROOT:-$repo_root/.snapshots}/$repo/$sha"

# Content-addressed by commit, so repeated submissions of the same code share one snapshot and a
# resubmission after a crash is byte-identical to the original.
if [[ ! -d "$snapshot" ]]; then
    mkdir -p "$snapshot"
    git archive "$sha" | tar -x -C "$snapshot"
fi

# `.env` is gitignored, so it is not in the archive. Copy rather than symlink: a symlink would let
# a later edit change a running job's configuration, which is the thing being prevented here.
if [[ -f .env ]]; then
    cp -n .env "$snapshot/.env" || true
fi

# A relative path resolves against the process's working directory. From a snapshot that means a
# fresh empty directory inside the snapshot, not the real dataset -- silently, with no error.
if [[ -f .env ]]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[A-Z_]*(DIR|PATH|ROOT)$ ]] || continue
        value="${value%\"}"; value="${value#\"}"
        [[ -z "$value" || "$value" == /* || "$value" == \$* || "$value" == '~'* ]] && continue
        echo "$key=$value is relative; make it absolute in .env before submitting." >&2
        echo "From a snapshot it would resolve inside $snapshot, not where you meant." >&2
        exit 1
    done < <(grep -E '^[A-Z_]+=' .env || true)
fi

# Environments are addressed by the lockfile they were built from: same lock, same environment,
# safely shared. Freshness (lock matches pyproject.toml) is checked here, in the live tree, where
# an editable `path = "../foo"` pypi-dependency resolves correctly against the real repo root.
# Checking it instead from inside the snapshot -- a different depth/location -- makes pixi see even
# a fully up-to-date lock as stale, purely from re-resolving that path from the wrong place;
# rewriting it to an absolute path in the snapshot's pyproject.toml doesn't fix this, since
# pixi.lock carries its own relative record of the same path, re-resolved the same wrong way
# regardless of what pyproject.toml says. So: validate freshness here with `--locked` (the ordinary
# dev workflow already keeps this true), then build the snapshot's copy with `--frozen`, which
# installs exactly what's pinned without re-deriving freshness -- but it still needs to physically
# read the dependency's source from that same relative path, so recreate it as a symlink to where
# it really is; unlike the freshness check, plain file access doesn't care that the symlink sits one
# level removed from the real target.
if [[ -f pixi.lock ]]; then
    pixi install --locked >&2
    while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        real_target=$(cd "$repo_root" && realpath -m "$rel")
        link_path=$(realpath -m "$snapshot/$rel")
        mkdir -p "$(dirname "$link_path")"
        ln -sfn "$real_target" "$link_path"
    done < <(grep -oP '^\S+\s*=\s*\{\s*path\s*=\s*"\K[^"]+(?="\s*,\s*editable\s*=\s*true\s*\})' pyproject.toml 2>/dev/null | grep -v '^\.$')

    lock_hash=$(sha256sum pixi.lock | cut -c1-16)
    # Same rationale as SNAPSHOT_ROOT above: project-relative default, override with ENV_ROOT.
    env_dir="${ENV_ROOT:-$repo_root/.envs}/$repo-$lock_hash"
    if [[ ! -d "$env_dir" ]]; then
        # Build into the snapshot, then move it out: pixi installs to <project>/.pixi and has no
        # flag to target another directory. Build under a unique name and rename, so two
        # submissions racing on the same lock cannot see a half-built environment.
        staging="$env_dir.$$"
        mkdir -p "$(dirname "$env_dir")"
        # --all, not just the default environment: a project with one environment per tool (say a
        # model whose dependencies cannot coexist with the others') runs its jobs as
        # `pixi run -e <env>`, and an environment missing from the snapshot gets built at job time
        # -- which needs network, which compute nodes do not have.
        (cd "$snapshot" && pixi install --all --frozen >&2)
        mv "$snapshot/.pixi" "$staging"
        mv -T "$staging" "$env_dir" 2>/dev/null || rm -rf "$staging"
    fi
    ln -sfn "$env_dir" "$snapshot/.pixi"
fi

# Slurm does not create a missing --output directory: the job fails before writing any log, so
# the failure leaves nothing to read. Create it here, in the live tree, and link the snapshot to it.
mkdir -p "$repo_root/.logs/$log_name"
ln -sfn "$repo_root/.logs" "$snapshot/.logs"

echo "$snapshot"
