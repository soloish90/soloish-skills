#!/usr/bin/env bash
set -euo pipefail

REPO="soloish/soloish-skills"
REF="main"
SKILLS=()
TARGETS=()
ALL_SKILLS=0
YES=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Install skills from soloish-skills.

Usage:
  install.sh [options]

Options:
  --skill NAME       Skill to install. Repeatable.
  --all-skills       Install every skill.
  --target NAME      codex, codex-legacy, claude, or all. Repeatable.
  --repo OWNER/REPO  GitHub repo. Default: soloish/soloish-skills.
  --ref REF          Git ref. Default: main.
  -y, --yes          Replace existing installed skills without prompting.
  --dry-run          Show what would be installed.
  -h, --help         Show help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill) SKILLS+=("${2:?missing skill name}"); shift 2 ;;
    --all-skills) ALL_SKILLS=1; shift ;;
    --target) TARGETS+=("${2:?missing target name}"); shift 2 ;;
    --repo) REPO="${2:?missing repo}"; shift 2 ;;
    --ref) REF="${2:?missing ref}"; shift 2 ;;
    -y|--yes) YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

read_from_tty() {
  local prompt="$1"
  local value=""
  if [[ -r /dev/tty ]]; then
    printf "%s" "$prompt" > /dev/tty
    IFS= read -r value < /dev/tty || true
  fi
  printf "%s" "$value"
}

split_csv_items() {
  local item part
  for item in "$@"; do
    IFS=',' read -ra parts <<< "$item"
    for part in "${parts[@]}"; do
      [[ -n "$part" ]] && printf "%s\n" "$part"
    done
  done
}

unique_lines() {
  awk '!seen[$0]++'
}

target_dir() {
  case "$1" in
    codex) printf "%s\n" "$HOME/.agents/skills" ;;
    codex-legacy) printf "%s\n" "${CODEX_HOME:-$HOME/.codex}/skills" ;;
    claude) printf "%s\n" "$HOME/.claude/skills" ;;
    *) echo "Unknown target: $1" >&2; exit 2 ;;
  esac
}

target_label() {
  case "$1" in
    codex) printf "Codex" ;;
    codex-legacy) printf "Codex legacy" ;;
    claude) printf "Claude Code" ;;
  esac
}

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

archive="$tmp_dir/repo.tar.gz"
archive_url="https://github.com/$REPO/archive/refs/heads/$REF.tar.gz"
if ! curl -fsSL "$archive_url" -o "$archive"; then
  archive_url="https://github.com/$REPO/archive/$REF.tar.gz"
  curl -fsSL "$archive_url" -o "$archive"
fi

tar -xzf "$archive" -C "$tmp_dir"
repo_root="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
skills_root="$repo_root/skills"
if [[ ! -d "$skills_root" ]]; then
  echo "No skills directory found in $REPO@$REF" >&2
  exit 1
fi

mapfile -t available_skills < <(find "$skills_root" -mindepth 2 -maxdepth 2 -name SKILL.md -print | sed -E 's#^.*/skills/([^/]+)/SKILL.md#\1#' | sort)
if [[ ${#available_skills[@]} -eq 0 ]]; then
  echo "No skills found in $REPO@$REF" >&2
  exit 1
fi

if [[ $ALL_SKILLS -eq 1 ]]; then
  selected_skills=("${available_skills[@]}")
elif [[ ${#SKILLS[@]} -gt 0 ]]; then
  mapfile -t selected_skills < <(split_csv_items "${SKILLS[@]}" | unique_lines)
else
  echo "Skills:" > /dev/tty
  for i in "${!available_skills[@]}"; do
    printf "  %d. %s\n" "$((i + 1))" "${available_skills[$i]}" > /dev/tty
  done
  answer="$(read_from_tty "Choose skills by number/name, comma-separated, or Enter for all: ")"
  if [[ -z "$answer" ]]; then
    selected_skills=("${available_skills[@]}")
  else
    selected_skills=()
    IFS=',' read -ra choices <<< "$answer"
    for choice in "${choices[@]}"; do
      choice="$(printf "%s" "$choice" | xargs)"
      if [[ "$choice" =~ ^[0-9]+$ ]]; then
        index=$((choice - 1))
        [[ $index -ge 0 && $index -lt ${#available_skills[@]} ]] || { echo "Invalid skill selection: $choice" >&2; exit 2; }
        selected_skills+=("${available_skills[$index]}")
      else
        selected_skills+=("$choice")
      fi
    done
  fi
fi

for skill in "${selected_skills[@]}"; do
  if [[ ! -f "$skills_root/$skill/SKILL.md" ]]; then
    echo "Unknown skill: $skill" >&2
    exit 2
  fi
done

if [[ ${#TARGETS[@]} -gt 0 ]]; then
  mapfile -t selected_targets < <(split_csv_items "${TARGETS[@]}" | sed 's/^all$/codex\nclaude/' | unique_lines)
else
  target_options=(codex claude codex-legacy)
  echo "Targets:" > /dev/tty
  for i in "${!target_options[@]}"; do
    printf "  %d. %s\n" "$((i + 1))" "${target_options[$i]}" > /dev/tty
  done
  answer="$(read_from_tty "Choose targets by number/name, comma-separated, or Enter for codex,claude: ")"
  if [[ -z "$answer" ]]; then
    selected_targets=(codex claude)
  else
    selected_targets=()
    IFS=',' read -ra choices <<< "$answer"
    for choice in "${choices[@]}"; do
      choice="$(printf "%s" "$choice" | xargs)"
      if [[ "$choice" == "all" ]]; then
        selected_targets+=(codex claude)
      elif [[ "$choice" =~ ^[0-9]+$ ]]; then
        index=$((choice - 1))
        [[ $index -ge 0 && $index -lt ${#target_options[@]} ]] || { echo "Invalid target selection: $choice" >&2; exit 2; }
        selected_targets+=("${target_options[$index]}")
      else
        selected_targets+=("$choice")
      fi
    done
    mapfile -t selected_targets < <(printf "%s\n" "${selected_targets[@]}" | unique_lines)
  fi
fi

for target in "${selected_targets[@]}"; do
  case "$target" in codex|codex-legacy|claude) ;; *) echo "Unknown target: $target" >&2; exit 2 ;; esac
done

existing=()
for target in "${selected_targets[@]}"; do
  root="$(target_dir "$target")"
  for skill in "${selected_skills[@]}"; do
    [[ -e "$root/$skill" ]] && existing+=("$root/$skill")
  done
done

if [[ ${#existing[@]} -gt 0 && $YES -eq 0 && $DRY_RUN -eq 0 ]]; then
  echo "These installed skills will be replaced:" > /dev/tty
  printf "  %s\n" "${existing[@]}" > /dev/tty
  answer="$(read_from_tty "Replace them? [y/N] ")"
  [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]] || { echo "Install cancelled."; exit 1; }
fi

for target in "${selected_targets[@]}"; do
  root="$(target_dir "$target")"
  label="$(target_label "$target")"
  echo "$label: $root"
  for skill in "${selected_skills[@]}"; do
    dest="$root/$skill"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "Would install $skill -> $dest"
    else
      mkdir -p "$root"
      rm -rf "$dest"
      cp -R "$skills_root/$skill" "$dest"
      echo "Installed $skill -> $dest"
    fi
  done
done

echo "Done."
