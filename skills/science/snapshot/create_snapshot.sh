#!/usr/bin/env bash
# Freeze one commit in <repo>/.snapshots/<commit>/ (its files, its own pixi environment, a copy of
# .env, snapshot.yaml written last) and print the snapshot's path. Run from the live checkout.
#
#   bash <snapshot skill dir>/create_snapshot.sh [--commit <sha>] [--log <name>]...
#
# Safe to call again: a finished snapshot is reused, only the log folders are added; an unfinished
# one (no snapshot.yaml) is finished. Why each step exists: SKILL.md next to this file.
set -euo pipefail

usage="usage: create_snapshot.sh [--commit <sha>] [--log <name>]..."
commit=""
logs=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit) commit=${2:?$usage}; shift 2 ;;
        --log)
            # A relative path below .logs/<commit>/: no leading /, no empty, . or .. segment.
            [[ "${2:-}" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ \
                && "/$2/" != */./* && "/$2/" != */../* ]] \
                || { echo "--log needs a relative path of named segments; $usage" >&2; exit 2; }
            logs+=("$2"); shift 2 ;;
        *) echo "$usage" >&2; exit 2 ;;
    esac
done

repo_root=$(git rev-parse --show-toplevel)
# A snapshot has no .git, so git there finds the live checkout and its HEAD, not the snapshot's.
if [[ "$(pwd -P)/" == "$(cd "$repo_root" && pwd -P)/.snapshots/"* ]]; then
    echo "run create_snapshot from the live checkout, not from a snapshot" >&2
    exit 1
fi
cd "$repo_root"

if [[ -z "$commit" ]]; then
    # Only an implicit HEAD misleads: uncommitted changes look included and are not. Tracked files
    # only, so one stray untracked file does not block every submission.
    if ! git diff-index --quiet HEAD --; then
        echo "uncommitted changes to tracked files: commit them, or pass --commit <sha>" >&2
        exit 1
    fi
    commit=HEAD
fi
commit=$(git rev-parse --verify --quiet "$commit^{commit}") \
    || { echo "not a commit in $repo_root" >&2; exit 1; }
snapshot="$repo_root/.snapshots/$commit"
log_dir="$repo_root/.logs/$commit"

# Logs live in the checkout, not in the snapshot: deleting a snapshot must not delete the record of
# its jobs. Slurm does not create a missing --output folder, and a job that cannot open its log
# fails without writing one, so the folders are made here.
mkdir -p "$log_dir"
for name in ${logs[@]+"${logs[@]}"}; do mkdir -p "$log_dir/$name"; done

if [[ -f "$snapshot/snapshot.yaml" ]]; then
    echo "$snapshot"
    exit 0
fi

exec 2> >(tee -a "$log_dir/snapshot.log" >&2)
echo "$(date -u +%FT%TZ) create_snapshot $commit" >&2

# A relative path resolves against the working directory: from a snapshot that is a folder inside
# the snapshot, not the real data, and it fails as "no data", not as an error.
if [[ -f .env ]]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[A-Z_]*(DIR|PATH|ROOT)$ ]] || continue
        value="${value%\"}"; value="${value#\"}"
        [[ -z "$value" || "$value" == /* || "$value" == \$* || "$value" == '~'* ]] && continue
        echo "$key=$value in .env is relative: make it absolute, or it resolves inside $snapshot" >&2
        exit 1
    done < <(grep -E '^[A-Z_]+=' .env || true)
fi

# No snapshot.yaml means an earlier call was killed: extract again over it. Same commit, same files,
# so this completes a partial tree and changes nothing in a whole one.
mkdir -p "$snapshot"
git archive "$commit" | tar -x -C "$snapshot"

# Copied, not linked: a later edit of .env must not change the settings of a running job.
if [[ -f .env ]]; then cp .env "$snapshot/.env"; fi

lock_sha=null
if [[ -f "$snapshot/pixi.lock" ]]; then
    # One environment per snapshot, installed from the commit's own lock: nothing outside the
    # snapshot can change it. --all: a job may run `pixi run -e <env>`, and a compute node has no
    # network to install a missing one.
    mode=--locked
    # An editable dependency outside the repo (`path = "../sibling"`) resolves against the
    # snapshot's folder, where it does not exist: link it to its real place. pixi's lock check
    # rejects that link, so such a project installs with --frozen (exactly what is pinned, with no
    # lock check). shortcut: the lock is then not checked against the manifest; check it with
    # `pixi install --locked` in the checkout if a stale lock ever gets through.
    while IFS= read -r rel; do
        [[ "$rel" == ../* ]] || continue
        mkdir -p "$(dirname "$snapshot/$rel")"
        ln -sfn "$repo_root/$rel" "$snapshot/$rel"
        mode=--frozen
    done < <(cat "$snapshot/pyproject.toml" "$snapshot/pixi.toml" 2>/dev/null | sed -nE \
        's/^[^#=]+=[[:space:]]*\{[[:space:]]*path[[:space:]]*=[[:space:]]*"([^"]+)"[[:space:]]*,[[:space:]]*editable[[:space:]]*=[[:space:]]*true.*/\1/p')
    (cd "$snapshot" && pixi install --all "$mode") >&2
    lock_sha=$({ sha256sum 2>/dev/null || shasum -a 256; } < "$snapshot/pixi.lock" | cut -d' ' -f1)
fi

ln -sfn "$log_dir" "$snapshot/.logs"

# Written last: a snapshot without it is unfinished, and the next call finishes it.
cat > "$snapshot/snapshot.yaml" <<EOF
commit: $commit
pixi_lock_sha256: $lock_sha
created: $(date -u +%FT%TZ)
EOF
echo "$(date -u +%FT%TZ) done $snapshot" >&2
echo "$snapshot"
