#!/usr/bin/env bash
# Poll GitHub PRs and print one line per new/edited activity item.
# Usage: watch-prs.sh [--interval SECS] [--once] [--replay] [--include-self] [--state-dir DIR] PR...
#   PR: URL, owner/repo#N, or N (repo of the current directory)
# Seen state lives in --state-dir (default ${XDG_CACHE_HOME:-~/.cache}/watch-prs) so re-arming does not
# repeat events. Use one dir per watcher: watchers sharing a dir steal each other's events.
# First sight of a PR records a baseline silently (use --replay to emit existing items).
# Items authored by the authenticated user are skipped unless --include-self (own drafts always show).
set -uo pipefail

interval=60; once=0; replay=0; self=0; prs=()
state_dir=${XDG_CACHE_HOME:-$HOME/.cache}/watch-prs
while [[ $# -gt 0 ]]; do
  case $1 in
    --interval) interval=$2; shift 2 ;;
    --once) once=1; shift ;;
    --replay) replay=1; shift ;;
    --include-self) self=1; shift ;;
    --state-dir) state_dir=$2; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) prs+=("$1"); shift ;;
  esac
done
[[ ${#prs[@]} -gt 0 ]] || { echo "usage: watch-prs.sh [--interval S] [--once] [--replay] [--include-self] [--state-dir DIR] PR... (see --help)" >&2; exit 2; }

mkdir -p "$state_dir"
me=$(gh api user --jq .login 2>/dev/null || echo "")

normalize() { # -> owner/repo N
  local p=$1
  if [[ $p =~ github\.com/([^/]+/[^/]+)/pull/([0-9]+) ]]; then echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
  elif [[ $p =~ ^([^/#]+/[^/#]+)#([0-9]+)$ ]]; then echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
  elif [[ $p =~ ^[0-9]+$ ]]; then echo "$(gh repo view --json nameWithOwner --jq .nameWithOwner) $p"
  else echo "bad PR spec: $p" >&2; return 1; fi
}

# Emits TSV: key<TAB>version<TAB>author<TAB>message
collect() {
  local repo=$1 n=$2 tag="[$1#$2]"
  local short='(.body // "" | gsub("(?s)<!--.*?-->"; "") | gsub("\\s+"; " ") | ltrimstr(" ") | if length > 300 then .[:300] + "…" else . end)'

  gh api --paginate "repos/$repo/issues/$n/comments" --jq ".[] |
    [\"ic:\(.id)\", .updated_at, .user.login, \"$tag comment by \(.user.login): \($short) \(.html_url)\"] | @tsv" || return 1

  gh api --paginate "repos/$repo/pulls/$n/comments" --jq ".[] |
    [\"rc:\(.id)\", .updated_at, .user.login, \"$tag review-comment by \(.user.login) on \(.path):\(.line // .original_line // \"?\")\(if .in_reply_to_id then \" (reply)\" else \"\" end): \($short) \(.html_url)\"] | @tsv" || return 1

  local reviews; reviews=$(gh api --paginate "repos/$repo/pulls/$n/reviews" --jq '.[]' 2>/dev/null | jq -s .) || return 1
  jq -r --arg tag "$tag" ".[] | select(.state != \"PENDING\") |
    select(.state != \"COMMENTED\" or ((.body // \"\") != \"\")) |
    [\"rv:\(.id)\", (.submitted_at // \"\") + (.body // \"\" | length | tostring), .user.login, \"\(\$tag) review \(.state) by \(.user.login): \($short) \(.html_url)\"] | @tsv" <<<"$reviews" | tr -d '\r'

  # Pending (draft) reviews are only visible to their author, i.e. the authenticated user.
  local rid
  for rid in $(jq -r '.[] | select(.state == "PENDING") | .id' <<<"$reviews" | tr -d '\r'); do
    gh api --paginate "repos/$repo/pulls/$n/reviews/$rid/comments" --jq ".[] |
      [\"dc:\(.id)\", .updated_at, \"-\", \"$tag DRAFT comment (yours, unsubmitted) on \(.path) (diff position \(.position // .original_position // \"?\")): \($short)\"] | @tsv" || true
  done

  gh pr view "$n" -R "$repo" --json state,isDraft,headRefOid,reviewDecision,mergeable --jq \
    "[\"st\", \"\(.state)|\(.isDraft)|\(.reviewDecision)\", \"-\", \"$tag state=\(.state) draft=\(.isDraft) review=\(if (.reviewDecision // \"\") == \"\" then \"none\" else .reviewDecision end)\"],
     [\"head\", .headRefOid, \"-\", \"$tag new head commit \(.headRefOid[:10])\"] | @tsv" || return 1

  gh pr checks "$n" -R "$repo" --json name,bucket,link --jq ".[] | select(.bucket != \"pending\") |
    [\"ck:\(.name)\", .bucket, \"-\", \"$tag check \(.name): \(.bucket) \(.link)\"] | @tsv" 2>/dev/null || true
}

poll() {
  local spec repo n file tmp key ver author msg old
  for spec in "${prs[@]}"; do
    read -r repo n < <(normalize "$spec") || continue
    file="$state_dir/${repo//\//_}_$n.tsv"
    tmp=$(mktemp)
    if ! collect "$repo" "$n" >"$tmp" 2>/dev/null; then
      echo "[$repo#$n] poll failed (will retry)"; rm -f "$tmp"; continue
    fi
    if [[ ! -f $file && $replay -eq 0 ]]; then
      cut -f1,2 "$tmp" >"$file.new" && mv "$file.new" "$file"
      echo "[$repo#$n] watching (baseline: $(wc -l <"$tmp") existing items)"
    else
      touch "$file"
      while IFS=$'\t' read -r key ver author msg; do
        [[ $self -eq 0 && -n $me && $author == "$me" ]] && continue
        old=$(awk -F'\t' -v k="$key" '$1==k{print $2}' "$file")
        if [[ -z $old ]]; then echo "$msg"
        elif [[ $old != "$ver" ]]; then
          case $key in st|head|ck:*) echo "$msg" ;; *) echo "(edited) $msg" ;; esac
        fi
      done <"$tmp"
      # Drafts that disappeared were submitted or deleted.
      awk -F'\t' 'NR==FNR{now[$1]=1; next} $1 ~ /^dc:/ && !($1 in now){print $1}' "$tmp" "$file" |
        while read -r key; do echo "[$repo#$n] draft ${key#dc:} no longer pending (submitted or deleted)"; done
      cut -f1,2 "$tmp" >"$file.new" && mv "$file.new" "$file"
    fi
    rm -f "$tmp"
  done
}

while true; do
  poll
  [[ $once -eq 1 ]] && break
  sleep "$interval"
done
