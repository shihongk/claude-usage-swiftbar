#!/bin/bash
# <xbar.title>Claude Usage</xbar.title>
# <xbar.version>v1.1</xbar.version>
# <xbar.desc>Claude Pro 5-hour and weekly usage in the menu bar (unofficial claude.ai endpoints)</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

SERVICE="claude-usage"
CACHE_DIR="$HOME/Library/Caches/claude-usage"
ORG_FILE="$CACHE_DIR/org_id"
LAST_FILE="$CACHE_DIR/last"   # sess_pct|sess_reset_epoch|wk_pct|wk_reset_epoch|fetched_epoch
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
USAGE_URL="https://claude.ai/settings/usage"
mkdir -p "$CACHE_DIR"

# ---------- JSON helpers (jq, falling back to osascript JXA) ----------
JS='function run(a){var j=JSON.parse(a[1]);
 if(a[0]=="org"){if(!Array.isArray(j))return "";
  var o=j.find(function(x){return (x.capabilities||[]).indexOf("chat")>=0})||j[0];return (o&&o.uuid)||"";}
 if(!j||typeof j!="object"||(!("five_hour" in j)&&!("seven_day" in j)))return "BAD";
 var f=j.five_hour||{},s=j.seven_day||{};
 return [f.utilization,f.resets_at,s.utilization,s.resets_at].map(function(x){return x==null?"":x}).join("|");}'

json_org() {
  if [ -x /usr/bin/jq ]; then
    printf '%s' "$1" | /usr/bin/jq -r '(map(select((.capabilities//[])|index("chat")))[0] // .[0]).uuid // empty' 2>/dev/null
  else
    osascript -l JavaScript -e "$JS" org "$1" 2>/dev/null
  fi
}
json_usage() {  # prints "BAD" or sess_pct|sess_reset|wk_pct|wk_reset
  if [ -x /usr/bin/jq ]; then
    printf '%s' "$1" | /usr/bin/jq -r 'if type=="object" and (has("five_hour") or has("seven_day"))
      then [.five_hour.utilization // "", .five_hour.resets_at // "", .seven_day.utilization // "", .seven_day.resets_at // ""] | join("|")
      else "BAD" end' 2>/dev/null || echo BAD
  else
    osascript -l JavaScript -e "$JS" usage "$1" 2>/dev/null || echo BAD
  fi
}

# ---------- HTTP (key goes via curl config on stdin, never argv/logs) ----------
HTTP_CODE=000; BODY=""
http_get() {
  local out
  out=$(printf 'header = "Cookie: sessionKey=%s"\n' "$KEY" | curl -sS -m 20 -K - \
    -H "Accept: application/json" -H "User-Agent: $UA" \
    -H "Referer: https://claude.ai" -H "Origin: https://claude.ai" \
    -w $'\n%{http_code}' "$1" 2>/dev/null)
  HTTP_CODE="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
  [ -z "$HTTP_CODE" ] && HTTP_CODE=000
}
# ok | auth | blocked
classify() {
  [ "$HTTP_CODE" = 200 ] && { echo ok; return; }
  if printf '%s' "$BODY" | grep -qiE '<html|just a moment|cloudflare'; then echo blocked; return; fi
  case "$HTTP_CODE" in 401|403) echo auth ;; *) echo blocked ;; esac
}

# ---------- time helpers ----------
iso_to_epoch() {  # "2026-11-17T13:00:00.123456+00:00" -> epoch
  local s="$1"
  [ -z "$s" ] && return
  s=$(printf '%s' "$s" | sed -E 's/\.[0-9]+//; s/Z$/+0000/; s/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
  date -j -f "%Y-%m-%dT%H:%M:%S%z" "$s" +%s 2>/dev/null
}
fmt_clock() { date -r "$1" "+%-I:%M %p"; }
fmt_week()  { date -r "$1" "+%a %-I:%M %p"; }
fmt_left() {  # seconds -> "2h 14m"
  local s=$1
  [ "$s" -le 0 ] && { echo "now"; return; }
  local d=$((s/86400)) h=$(((s%86400)/3600)) m=$(((s%3600)/60))
  if [ $d -gt 0 ]; then echo "${d}d ${h}h"; elif [ $h -gt 0 ]; then echo "${h}h ${m}m"; else echo "${m}m"; fi
}
round() { printf '%.0f' "${1:-0}" 2>/dev/null || echo 0; }

# ---------- menu bar icon (Stats-style: label over value), drawn with AppKit via JXA ----------
ICON_JS=$(cat <<'ICONEOF'
ObjC.import('AppKit');
function run(a){
  var sp=a[0], wp=a[1], dark=a[2]=="1", rt=(a[3]&&a[3]!="-")?a[3]:"";
  var S=2, H=22; // S = retina scale
  var lab = dark? [1,1,1,0.6] : [0,0,0,0.6];
  var base= dark? [1,1,1,1] : [0,0,0,1];
  var claude=[0.851,0.467,0.341,1];
  function col(p){ return p>=90?[1,0.27,0.23,1]:(p>=70?[1,0.62,0.04,1]:base); }
  function ns(c){return $.NSColor.colorWithSRGBRedGreenBlueAlpha(c[0],c[1],c[2],c[3]);}
  function draw(str,sz,w,c,mono,x,y){
    var f = mono? $.NSFont.monospacedDigitSystemFontOfSizeWeight(sz,w) : $.NSFont.systemFontOfSizeWeight(sz,w);
    var d=$.NSMutableDictionary.alloc.init;
    d.setObjectForKey(f,$.NSFontAttributeName);
    d.setObjectForKey(ns(c),$.NSForegroundColorAttributeName);
    var s=$(str); var size=s.sizeWithAttributes(d);
    s.drawAtPointWithAttributes($.NSMakePoint(x,y),d);
    return size.width;
  }
  function width(str,sz,w,mono){
    var f = mono? $.NSFont.monospacedDigitSystemFontOfSizeWeight(sz,w) : $.NSFont.systemFontOfSizeWeight(sz,w);
    var d=$.NSMutableDictionary.alloc.init; d.setObjectForKey(f,$.NSFontAttributeName);
    return $(str).sizeWithAttributes(d).width;
  }
  var cols=(rt?[["RESETS",rt,0]]:[]).concat([["5H",sp+"%",sp],["7D",wp+"%",wp]]);
  var glyphW=width("✳",15,0.0,false), gap=13, pad=1;
  var widths=cols.map(function(c){return Math.max(width(c[0],8,0.3,false),width(c[1],12,0.3,true));});
  var W=Math.ceil(pad+glyphW+gap+widths.reduce(function(a,b){return a+b+gap;},0)-gap+pad);
  var rep=$.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    $(), W*S, H*S, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0);
  rep.size = $.NSMakeSize(W,H);
  var ctx=$.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep);
  $.NSGraphicsContext.saveGraphicsState; $.NSGraphicsContext.setCurrentContext(ctx);
  
  var x=pad;
  draw("✳",15,0.3,claude,false,x,(H-15*1.2)/2);
  x+=glyphW+gap;
  for(var i=0;i<cols.length;i++){
    var w=widths[i];
    var lw=width(cols[i][0],8,0.3,false), vw=width(cols[i][1],12,0.3,true);
    draw(cols[i][0],8,0.3,lab,false,x+(w-lw)/2,11.5);
    draw(cols[i][1],12,0.3,col(cols[i][2]),true,x+(w-vw)/2,0.5);
    x+=w+gap;
  }
  $.NSGraphicsContext.restoreGraphicsState;
  var png=rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG,$());
  return ObjC.unwrap(png.base64EncodedStringWithOptions(0));
}
ICONEOF
)
make_icon() {  # $1=session% $2=weekly% $3=reset time ("1:30 pm" or "-") -> base64 PNG
  local dark=0
  [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ] && dark=1
  osascript -l JavaScript -e "$ICON_JS" "$1" "$2" "$dark" "${3:--}" 2>/dev/null | tr -d "\n"
}

# ---------- output ----------
common_footer() {
  echo "Open Usage page | href=$USAGE_URL"
  echo "Refresh now | refresh=true"
  echo "Refresh Claude Code login | bash=\"$0\" param1=--refresh terminal=false refresh=true"
}

show_relogin() {
  echo "◔ re-login"
  echo "---"
  echo "$1 | color=red"
  echo "To get a new sessionKey:"
  echo "1. Open claude.ai in your browser and sign in"
  echo "2. DevTools → Application → Cookies → claude.ai"
  echo "3. Copy the value of sessionKey (starts with sk-ant-sid01-)"
  echo "4. Run ./setup.sh and paste it"
  echo "---"
  common_footer
}

show_unexpected() {
  echo "◔ ?"
  echo "---"
  echo "Unexpected response (HTTP $HTTP_CODE) | color=red"
  printf '%s\n' "$BODY" | head -c 1500 | tr '\r' ' ' | while IFS= read -r line; do
    echo "${line//|/¦} | font=Menlo size=11 trim=false"
  done
  echo "---"
  common_footer
}

render() {  # $1 = stale flag (0/1); reads LAST_FILE
  local sp sr wp wr ft now
  IFS='|' read -r sp sr wp wr ft < "$LAST_FILE"
  now=$(date +%s)
  local spi wpi hi color=""
  spi=$(round "$sp"); wpi=$(round "$wp")
  hi=$spi; [ "$wpi" -gt "$hi" ] && hi=$wpi
  if [ "$hi" -ge 90 ]; then color=" | color=red"
  elif [ "$hi" -ge 70 ]; then color=" | color=orange"; fi

  local rt="-"
  [ -n "$sr" ] && [ "$sr" -gt "$now" ] && rt=$(fmt_clock "$sr" | tr 'A-Z' 'a-z')
  local icon; icon=$(make_icon "$spi" "$wpi" "$rt")
  if [ -n "$icon" ]; then
    echo "| image=$icon"
  else
    echo "◔ ${spi}% · 7d ${wpi}%${color}"   # text fallback if drawing fails
  fi
  echo "---"
  if [ -n "$sr" ] && [ "$sr" -gt "$now" ]; then
    echo "Session: ${spi}%, resets in $(fmt_left $((sr-now))) (at $(fmt_clock "$sr"))"
  else
    echo "Session: ${spi}%, no active 5-hour window"
  fi
  if [ -n "$wr" ]; then
    echo "Weekly: ${wpi}%, resets $(fmt_week "$wr")"
  else
    echo "Weekly: ${wpi}%"
  fi
  local stale=""; [ "$1" = 1 ] && stale=" (stale)"
  echo "Last updated: $(fmt_clock "$ft")${stale}"
  echo "---"
  common_footer
}

# ---------- Claude Code login refresh ----------
# Runs a tiny headless Claude Code call; Claude Code refreshes its own OAuth token as a side effect.
# (Costs a trivial amount of usage; the plugin never touches the refresh token itself.)
refresh_login() {
  local bin=""
  for p in "$HOME/.local/bin/claude" /opt/homebrew/bin/claude /usr/local/bin/claude; do
    [ -x "$p" ] && { bin="$p"; break; }
  done
  [ -z "$bin" ] && return 1
  # 1-minute watchdog, run from the cache dir so no project context is loaded
  (cd "$CACHE_DIR" && /usr/bin/perl -e 'alarm 60; exec @ARGV' "$bin" -p "ok" --model haiku >/dev/null 2>&1)
}
if [ "$1" = "--refresh" ]; then refresh_login; exit 0; fi

# ---------- main ----------
fail_stale() {  # network/Cloudflare problem: use cache if we have it
  if [ -s "$LAST_FILE" ]; then render 1
  else
    echo "◔ ?"; echo "---"
    echo "Blocked or unreachable (HTTP $HTTP_CODE), no cached data yet | color=red"
    echo "---"; common_footer
  fi
  exit 0
}

save_and_render() {  # $1 = json body
  local parsed sp sr wp wr
  parsed=$(json_usage "$1")
  if [ "$parsed" = "BAD" ] || [ -z "$parsed" ]; then show_unexpected; exit 0; fi
  IFS='|' read -r sp sr wp wr <<< "$parsed"
  printf '%s|%s|%s|%s|%s\n' "${sp:-0}" "$(iso_to_epoch "$sr")" "${wp:-0}" "$(iso_to_epoch "$wr")" "$(date +%s)" > "$LAST_FILE"
  render 0
  exit 0
}

# --- Source 1: Claude Code OAuth login (api.anthropic.com, no Cloudflare challenge) ---
read_creds() {  # sets CREDS_FOUND, TOKEN, EXP
  local c
  c=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  CREDS_FOUND=""; TOKEN=""; EXP=0
  [ -z "$c" ] && return
  CREDS_FOUND=1
  if [ -x /usr/bin/jq ]; then
    TOKEN=$(printf '%s' "$c" | /usr/bin/jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    EXP=$(printf '%s' "$c" | /usr/bin/jq -r '.claudeAiOauth.expiresAt // 0' 2>/dev/null)
  else
    TOKEN=$(osascript -l JavaScript -e 'function run(a){var o=JSON.parse(a[0]).claudeAiOauth||{};return o.accessToken||""}' "$c" 2>/dev/null)
    EXP=$(osascript -l JavaScript -e 'function run(a){var o=JSON.parse(a[0]).claudeAiOauth||{};return String(o.expiresAt||0)}' "$c" 2>/dev/null)
  fi
}
token_valid() { [ -n "$TOKEN" ] && [ "${EXP:-0}" -gt $(( ($(date +%s) + 60) * 1000 )) ]; }

OAUTH_NOTE=""
read_creds
if [ -n "$CREDS_FOUND" ] && ! token_valid; then
  refresh_login && read_creds   # Claude Code renews its own token when it runs
fi
if [ -n "$CREDS_FOUND" ]; then
  if token_valid; then
    out=$(printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -m 20 -K - \
      -H "anthropic-beta: oauth-2025-04-20" -H "User-Agent: claude-code/2.1.5" \
      -H "Content-Type: application/json" -w $'\n%{http_code}' \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    HTTP_CODE="${out##*$'\n'}"; BODY="${out%$'\n'*}"; TOKEN=""
    case "$HTTP_CODE" in
      200) save_and_render "$BODY" ;;
      401|403) OAUTH_NOTE="Claude Code login was rejected (HTTP $HTTP_CODE)" ;;
      *) OAUTH_NET_FAIL=1 ;;
    esac
  else
    OAUTH_NOTE="Claude Code token expired and auto-refresh failed; run claude once"
  fi
fi

# --- Source 2: claude.ai sessionKey cookie (may be blocked by Cloudflare) ---
KEY=$(security find-generic-password -s "$SERVICE" -a sessionKey -w 2>/dev/null)
if [ -z "$KEY" ]; then
  [ -n "${OAUTH_NET_FAIL:-}" ] && fail_stale
  show_relogin "${OAUTH_NOTE:-No Claude Code login or sessionKey found}"; exit 0
fi

ORG=""; [ -s "$ORG_FILE" ] && ORG=$(cat "$ORG_FILE")

if [ -z "$ORG" ]; then
  http_get "https://claude.ai/api/organizations"
  case "$(classify)" in
    auth) show_relogin "claude.ai rejected the session key (HTTP $HTTP_CODE)"; exit 0 ;;
    blocked) fail_stale ;;
  esac
  ORG=$(json_org "$BODY")
  if [ -z "$ORG" ]; then show_unexpected; exit 0; fi
  printf '%s' "$ORG" > "$ORG_FILE"
fi

http_get "https://claude.ai/api/organizations/$ORG/usage"
case "$(classify)" in
  auth)
    rm -f "$ORG_FILE"
    show_relogin "claude.ai rejected the session key (HTTP $HTTP_CODE)"; exit 0 ;;
  blocked) fail_stale ;;
esac
save_and_render "$BODY"
