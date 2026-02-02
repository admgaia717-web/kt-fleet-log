#!/bin/bash
# 艦長日誌をGitHubに同期するスクリプト

LOG_DIR="/Users/user/Library/Mobile Documents/com~apple~CloudDocs/DoOS/K_Vault/艦長日誌"
REPO_DIR=~/clawd/fleet-log

# 日誌をコピー
cp "$LOG_DIR"/*.md "$REPO_DIR/logs/" 2>/dev/null

# Git操作
cd "$REPO_DIR"
git add -A
git commit -m "📜 艦長日誌更新 $(date +%Y-%m-%d)" 2>/dev/null

# GitHubにpush（リモートが設定されている場合）
if git remote | grep -q origin; then
    git push origin main 2>/dev/null && echo "✅ GitHub同期完了"
else
    echo "⚠️ リモートが未設定。gh repo create で設定してください"
fi
