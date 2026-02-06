#!/bin/bash
# append_auto_decision.sh - 自律判断ログ追記スクリプト
# 15分ごとに実行、auto_decision.jsonlに1件追記

set -e

JSONL_FILE="$HOME/clawd/fleet-log/auto_decision.jsonl"
INDEX_FILE="$HOME/clawd/fleet-log/index.html"
STATE_FILE="$HOME/clawd-data/STATE.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S+09:00")
TODAY=$(date +"%Y-%m-%d")

# ディレクトリ確保
mkdir -p "$(dirname "$JSONL_FILE")"
touch "$JSONL_FILE"

# 直近のdecision+priorityを取得（二重投稿対策）
LAST_ENTRY=$(tail -1 "$JSONL_FILE" 2>/dev/null || echo "{}")
LAST_DECISION=$(echo "$LAST_ENTRY" | jq -r '.decision // ""' 2>/dev/null || echo "")
LAST_PRIORITY=$(echo "$LAST_ENTRY" | jq -r '.priority // ""' 2>/dev/null || echo "")

# 現状チェック（簡易）
check_fleet_status() {
    # 4号機API遅延チェック
    if ssh -o ConnectTimeout=3 spock 'tail -5 ~/.clawdbot/logs/gateway.err.log 2>/dev/null' | grep -q "AbortError\|timeout" 2>/dev/null; then
        echo "P1|4号機API遅延継続中|Sonnet 4のAPI応答が不安定|レスポンス監視継続、Haikuフォールバック準備|0.8"
        return
    fi
    
    # SSL期限チェック（簡易）
    if [ -f "$HOME/clawd/fleet/requests.md" ] && grep -q "SSL\|期限" "$HOME/clawd/fleet/requests.md" 2>/dev/null; then
        echo "P0|SSL証明書の期限監視継続|SEC-001タスクが未完了|cronで自動チェック設定、アラート実装|0.85"
        return
    fi
    
    # 3号機状態チェック
    if ! ssh -o ConnectTimeout=3 laforge 'echo ok' >/dev/null 2>&1; then
        echo "P0|3号機SSH接続不可|laforgeへの接続がタイムアウト|手動再起動要請、SSH鍵再設定|0.95"
        return
    fi
    
    # 変化なし
    echo "P2|艦隊状態は安定|定期監視で異常なし|監視継続、次回15分後に再チェック|0.7"
}

# 判断生成
RESULT=$(check_fleet_status)
PRIORITY=$(echo "$RESULT" | cut -d'|' -f1)
DECISION=$(echo "$RESULT" | cut -d'|' -f2)
BECAUSE=$(echo "$RESULT" | cut -d'|' -f3)
NEXT_ACTION=$(echo "$RESULT" | cut -d'|' -f4)
CONFIDENCE=$(echo "$RESULT" | cut -d'|' -f5)

# 二重投稿チェック
if [ "$DECISION" = "$LAST_DECISION" ] && [ "$PRIORITY" = "$LAST_PRIORITY" ]; then
    echo "Skip: 同一判断のため追記なし (decision=$DECISION, priority=$PRIORITY)"
    exit 0
fi

# JSONレコード生成
JSON_RECORD=$(cat <<EOF
{"timestamp":"$TIMESTAMP","priority":"$PRIORITY","decision":"$DECISION","because":["$BECAUSE"],"next_actions":["$NEXT_ACTION"],"confidence":$CONFIDENCE,"links":["$STATE_FILE"]}
EOF
)

# 追記
echo "$JSON_RECORD" >> "$JSONL_FILE"
echo "Appended: $JSON_RECORD"

# index.html更新（今日の件数と最新5件）
update_index_html() {
    TODAY_COUNT=$(grep "$TODAY" "$JSONL_FILE" 2>/dev/null | wc -l | tr -d ' ')
    
    # 最新5件取得（P0/P1優先でソート）
    LATEST=$(tail -20 "$JSONL_FILE" | jq -s 'sort_by(.priority) | reverse | .[0:5]' 2>/dev/null)
    
    # HTML生成（シンプル版）
    CARDS=""
    for i in 0 1 2 3 4; do
        ENTRY=$(echo "$LATEST" | jq -r ".[$i] // empty" 2>/dev/null)
        [ -z "$ENTRY" ] && continue
        
        P=$(echo "$ENTRY" | jq -r '.priority')
        D=$(echo "$ENTRY" | jq -r '.decision')
        B=$(echo "$ENTRY" | jq -r '.because[0] // "監視継続"')
        N=$(echo "$ENTRY" | jq -r '.next_actions[0] // "-"')
        C=$(echo "$ENTRY" | jq -r '.confidence')
        
        case "$P" in
            P0) COLOR="#f85149" ;;
            P1) COLOR="#d29922" ;;
            *)  COLOR="#8b949e" ;;
        esac
        
        CARDS="$CARDS<div class=\"card\" style=\"border-left: 4px solid $COLOR;\"><span class=\"tag\" style=\"background:$COLOR;color:white;\">$P</span><strong>$D</strong><p style=\"margin:0.5rem 0;font-size:0.9em;color:#8b949e;\">理由: $B</p><p style=\"margin:0;font-size:0.85em;\">次: $N <span style=\"color:#3fb950;\">(conf=$C)</span></p></div>"
    done
    
    # index.htmlの該当セクションを更新（sedで置換）
    # 簡易実装：全体を再生成せず、件数だけ更新
    sed -i.bak "s/今日の自律判断 <span[^>]*>[^<]*<\/span>/今日の自律判断 <span style=\"font-size:0.7em;color:#8b949e;\">(${TODAY_COUNT}件)<\/span>/" "$INDEX_FILE" 2>/dev/null || true
    
    echo "Updated index.html: $TODAY_COUNT件"
}

update_index_html

# git push（オプション）
cd "$HOME/clawd/fleet-log"
git add -A >/dev/null 2>&1 || true
git commit -m "auto_decision: $PRIORITY $DECISION" >/dev/null 2>&1 || true
git push >/dev/null 2>&1 || true

echo "Done: $TIMESTAMP"
