#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EVA_ACTION=install
case "${1:-}" in
    uninstall|--uninstall)
        EVA_ACTION=uninstall
        shift
        ;;
    install|--install)
        shift
        ;;
    -h|--help|help)
        cat <<'EOF'
Usage:
  ./install.sh [THEME PROFILE] [options]
  ./install.sh --uninstall [options]

Without a theme and profile, an interactive terminal opens the theme chooser.
Use eva01, wunder or eva02 with 720p, 1080p or 1440p.

Options:
  --gfxmode WIDTHxHEIGHT  Choose an exact firmware graphics mode
  --dry-run              Preview changes without writing files
  --no-apply             Install only the eva command and theme catalog
  -h, --help             Show this help

The install and uninstall subcommands are also accepted.
After installation, use sudo eva to switch themes or sudo eva uninstall to remove.
EOF
        exit 0
        ;;
esac
exec python3 -B "$SCRIPT_DIR/bin/manage.py" "$EVA_ACTION" "$@"
