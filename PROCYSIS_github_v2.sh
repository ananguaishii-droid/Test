#!/usr/bin/env bash
BASE="$HOME/procysis"
CFG="$BASE/cfg"
STATE="$BASE/state"
LOG_FILE="$BASE/procysis.log"
mkdir -p "$CFG" "$STATE"
touch "$LOG_FILE"
R=$'\033[1;31m'; G=$'\033[1;32m'; Y=$'\033[1;33m'
C=$'\033[1;96m'; N=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
PKGS=()
URIS=()
SELECTED=()
REPLY_VAL=""
IN_PLACE=""
IN_VIP=""
CACHE_FREED_KB=0
CACHE_FOUND=0
STOP=0
JOIN_UA='Mozilla/5.0 (Linux; Android 10; Mobile) PROCYSIS/2'
FOUND_ID=""; FOUND_PLAYING=-1; FOUND_MAX=0; FOUND_NOTE=""
PRES_TYPE=-1; PRES_PLACE=""; PRES_ROOT=""; PRES_GAME=""
cfg_get() { if [ -s "$CFG/$1" ]; then cat "$CFG/$1"; else printf '%s' "${2:-}"; fi; }
cfg_set() { printf '%s' "$2" > "$CFG/$1"; }
log() {
  local lv="$1"; shift
  printf '[%s] [%s] %s\n' "$(date '+%F %T')" "$lv" "$*" >> "$LOG_FILE"
}
rotate_log() {
  if [ "$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$LOG_FILE" "$LOG_FILE.old"
    : > "$LOG_FILE"
  fi
}
pause() { stty sane 2>/dev/null; printf '\n%sกด Enter เพื่อกลับเมนู...%s' "$Y" "$N"; read -r _; }
ask() {
  local p="$1" d="$2" a shown
  shown="$d"
  [ "${#shown}" -gt 45 ] && shown="${shown:0:45}…"
  if [ -n "$d" ]; then printf '%s [%s] : ' "$p" "$shown"; else printf '%s : ' "$p"; fi
  read -r a
  a="${a//$'\r'/}"
  [ -z "$a" ] && a="$d"
  [ "$a" = "-" ] && a=""
  REPLY_VAL="$a"
}
fmt_mb() { awk -v k="${1:-0}" 'BEGIN{printf "%.1f", k/1024}'; }
onoff() { if [ "$1" = "1" ]; then echo "เปิด"; else echo "ปิด"; fi; }
trunc() {
  local t
  t=$(printf '%s' "$1" | tr '\n' ' ')
  if printf '%s' "$t" | LC_ALL=C grep -q '[^ -~]'; then printf '%s' "$t"; else printf '%s' "${t:0:$2}"; fi
}
ROOTSH_ON=0; ROOTSH_PID=0; ROOT_OUT=""; ROOT_RC=1
rootsh_run() {
  local mark line out="" rc
  [ "$ROOTSH_ON" = "1" ] || return 1
  kill -0 "$ROOTSH_PID" 2>/dev/null || { ROOTSH_ON=0; return 1; }
  mark="__PRC${RANDOM}${RANDOM}__"
  printf '%s\n' "$1; __rc=\$?; echo; echo ${mark}:\$__rc" >&8
  while IFS= read -r -t "${SU_TIMEOUT:-20}" -u 9 line; do
    case "$line" in
      "${mark}:"*)
        rc=${line#*:}
        while [ "${out: -1}" = $'\n' ]; do out=${out%?}; done
        ROOT_OUT="$out"; ROOT_RC="$rc"
        return 0 ;;
    esac
    out+="$line"$'\n'
  done
  ROOT_OUT="$out"
  rootsh_stop
  return 1
}
rootsh_start() {
  local sp fin fout
  [ "$ROOTSH_ON" = "1" ] && return 0
  sp=$(find_su) || return 1
  fin="$STATE/rootsh.in"; fout="$STATE/rootsh.out"
  rm -f "$fin" "$fout"
  mkfifo "$fin" "$fout" 2>/dev/null || return 1
  exec 8<>"$fin" 9<>"$fout"
  ( trap '' INT; exec "$sp" <"$fin" >"$fout" 2>&1 ) &
  ROOTSH_PID=$!
  ROOTSH_ON=1
  if rootsh_run 'echo __ROOT_READY__ $(id -u)' && grep -q '__ROOT_READY__ 0' <<<"$ROOT_OUT"; then
    log INFO "เปิด root shell แบบค้างไว้สำเร็จ"
    return 0
  fi
  log WARN "เปิด root shell ไม่สำเร็จ: $(trunc "$ROOT_OUT" 120)"
  rootsh_stop
  return 1
}
rootsh_stop() {
  [ "$ROOTSH_ON" = "1" ] || return 0
  printf 'exit\n' >&8 2>/dev/null
  kill "$ROOTSH_PID" 2>/dev/null
  exec 8>&- 9<&-
  rm -f "$STATE/rootsh.in" "$STATE/rootsh.out"
  ROOTSH_ON=0
}
su_run() {
  local out rc
  if [ "$ROOTSH_ON" = "1" ] && [ "$(cfg_get ROOT_PERSIST 1)" = "1" ] && rootsh_run "$1"; then
    printf '%s' "$ROOT_OUT"
    return "$ROOT_RC"
  fi
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout -k 3 "${SU_TIMEOUT:-20}" "$(find_su)" -c "$1" </dev/null 2>&1); rc=$?
  else
    out=$("$(find_su)" -c "$1" </dev/null 2>&1); rc=$?
  fi
  stty sane 2>/dev/null
  printf '%s' "$out"
  return "$rc"
}
banner() {
  local cols
  cols=$(tput cols 2>/dev/null); [[ "$cols" =~ ^[0-9]+$ ]] || cols="${COLUMNS:-60}"
  clear
  printf '\n%s' "$C"
  if [ "$cols" -ge 66 ]; then
    printf '  ██████╗ ██████╗  ██████╗  ██████╗██╗   ██╗███████╗██╗███████╗\n'
    printf '  ██╔══██╗██╔══██╗██╔═══██╗██╔════╝╚██╗ ██╔╝██╔════╝██║██╔════╝\n'
    printf '  ██████╔╝██████╔╝██║   ██║██║      ╚████╔╝ ███████╗██║███████╗\n'
    printf '  ██╔═══╝ ██╔══██╗██║   ██║██║       ╚██╔╝  ╚════██║██║╚════██║\n'
    printf '  ██║     ██║  ██║╚██████╔╝╚██████╗   ██║   ███████║██║███████║\n'
    printf '  ╚═╝     ╚═╝  ╚═╝ ╚═════╝  ╚═════╝   ╚═╝   ╚══════╝╚═╝╚══════╝\n'
  else
    printf '  █▀█ █▀█ █▀█ █▀▀ █ █ █▀▀ ▀█▀ █▀▀\n'
    printf '  █▀▀ █▀▄ █ █ █   ▀█▀ ▀▀█  █  ▀▀█\n'
    printf '  ▀   ▀ ▀ ▀▀▀ ▀▀▀  ▀  ▀▀▀ ▄█▄ ▀▀▀\n'
  fi
  printf '%s' "$N"
  printf '  %sR O B L O X   M U L T I - S C R E E N%s\n' "$BOLD" "$N"
  printf '  %sTermux  •  Redfinger  •  Android%s\n' "$C" "$N"
  local w=$((cols - 4))
  [ "$w" -gt 44 ] && w=44; [ "$w" -lt 10 ] && w=10
  printf '  %s%s%s\n\n' "$C" "$(hline ━ "$w")" "$N"
}
check_deps() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "กำลังติดตั้ง curl ..."
    pkg install -y curl >/dev/null 2>&1 || log ERROR "ติดตั้ง curl ไม่สำเร็จ"
  fi
  command -v am >/dev/null 2>&1 || log ERROR "ไม่พบคำสั่ง am"
  command -v pm >/dev/null 2>&1 || log ERROR "ไม่พบคำสั่ง pm"
  ls /sdcard >/dev/null 2>&1 || termux-setup-storage
  termux-wake-lock 2>/dev/null
}
detect_pkgs() {
  local filter
  filter=$(cfg_get PKG_FILTER roblox)
  pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://' \
    | grep -iE "$filter" | sort
}
load_pkgs() {
  local kw
  mapfile -t PKGS < <(detect_pkgs)
  if [ -z "${PKGS[0]:-}" ]; then
    printf '%s⚠ ไม่พบแพ็กเกจด้วยคำค้น "%s"%s\n' "$Y" "$(cfg_get PKG_FILTER roblox)" "$N"
    ask "พิมพ์คำค้นชื่อแพ็กเกจใหม่ (Enter = ยกเลิก)" ""
    kw="$REPLY_VAL"
    if [ -n "$kw" ]; then
      cfg_set PKG_FILTER "$kw"
      mapfile -t PKGS < <(detect_pkgs)
    fi
  fi
  if [ -z "${PKGS[0]:-}" ]; then
    PKGS=()
    log ERROR "ไม่พบแพ็กเกจ Roblox"
    printf '%s✗ ไม่พบแพ็กเกจ%s\n' "$R" "$N"
    pause
    return 1
  fi
  printf '%s✓ พบ %s แพ็กเกจ:%s\n' "$G" "${#PKGS[@]}" "$N"
  printf '   • %s\n' "${PKGS[@]}"
  log INFO "พบแพ็กเกจ ${#PKGS[@]}: ${PKGS[*]}"
  return 0
}
screen_enabled() { cfg_get "enabled.$1" 1; }
show_screen_list() {
  local i p enabled
  printf '\n%sหมายเลขจอ / แพ็กเกจ / สถานะโปรเซส%s\n' "$C" "$N"
  for i in "${!PKGS[@]}"; do
    p="${PKGS[$i]}"
    enabled=$(screen_enabled "$p")
    if [ "$enabled" = "1" ]; then
      printf '  %s[ใช้งาน]%s ' "$G" "$N"
    else
      printf '  %s[ปิดใช้งานในตัวจัดการ]%s ' "$Y" "$N"
    fi
    if command -v pidof >/dev/null 2>&1 && pidof "$p" >/dev/null 2>&1; then
      printf '%sRUNNING%s' "$G" "$N"
    else
      printf '%sSTOPPED/UNKNOWN%s' "$DIM" "$N"
    fi
    printf '  %s) %s\n' "$((i+1))" "$p"
  done
  printf '\n%sหมายเหตุ: STOPPED/UNKNOWN หมายถึงไม่พบโปรเซส หรือระบบไม่อนุญาตให้ตรวจสอบ%s\n' "$DIM" "$N"
}
parse_screen_selection() {
  local input="$1" token num
  local -A seen=()
  SELECTED=()
  if [ "$input" = "all" ]; then
    for ((num=1; num<=${#PKGS[@]}; num++)); do SELECTED+=("$((num-1))"); done
    return 0
  fi
  input="${input// /}"
  [[ -z "$input" ]] && return 1
  local IFS=','
  local -a tokens=()
  read -ra tokens <<< "$input"
  for token in "${tokens[@]}"; do
    [[ "$token" =~ ^[0-9]+$ ]] || return 1
    num=$((10#$token))
    (( num >= 1 && num <= ${#PKGS[@]} )) || return 1
    if [ -z "${seen[$num]:-}" ]; then
      SELECTED+=("$((num-1))")
      seen[$num]=1
    fi
  done
  [ "${#SELECTED[@]}" -gt 0 ]
}
norm_place() {
  local s="$1"
  case "$s" in
    */games/*) s=$(printf '%s' "$s" | sed -n 's#.*/games/\([0-9]*\).*#\1#p') ;;
  esac
  printf '%s' "$s" | tr -cd '0-9'
}
resolve_inputs() {
  IN_PLACE="$1"; IN_VIP="$2"
  case "$IN_PLACE" in
    *privateServerLinkCode=*|*share*code=*)
      [ -z "$IN_VIP" ] && IN_VIP="$IN_PLACE"
      IN_PLACE="" ;;
  esac
  IN_PLACE=$(norm_place "$IN_PLACE")
}
build_uri() {
  local place="$1" vip="$2" code pid
  if [ -n "$vip" ]; then
    case "$vip" in
      *privateServerLinkCode=*)
        code=$(printf '%s' "$vip" | sed -n 's/.*privateServerLinkCode=\([^&#]*\).*/\1/p')
        pid=$(printf '%s' "$vip" | sed -n 's#.*roblox.com/games/\([0-9]*\).*#\1#p')
        [ -n "$pid" ] && place="$pid"
        [ -n "$place" ] && [ -n "$code" ] && printf 'roblox://placeId=%s&linkCode=%s' "$place" "$code"
        return ;;
      *share*code=*)
        code=$(printf '%s' "$vip" | sed -n 's/.*[?&]code=\([^&#]*\).*/\1/p')
        [ -n "$code" ] && printf 'roblox://navigation/share_links?code=%s&type=Server' "$code"
        return ;;
      *)
        return ;;
    esac
  fi
  [ -n "$place" ] && printf 'roblox://placeId=%s' "$place"
}
valid_uri() {
  if printf '%s' "$1" | grep -Eq 'placeId=[0-9]+|[?&]code=[A-Za-z0-9]+'; then printf '%s' "$1"; fi
}
clear_cache() {
  local pkg="$1" d b sz found=0 why bases first
  bases="${CACHE_BASES:-/sdcard /storage/emulated/0}"
  first="${bases%% *}"
  CACHE_FREED_KB=0; CACHE_FOUND=0
  for b in $bases; do
    for d in "$b/Android/data/$pkg/cache" "$b/Android/data/$pkg/code_cache"; do
      if [ -d "$d" ]; then
        found=1
        sz=$(du -sk "$d" 2>/dev/null | cut -f1)
        CACHE_FREED_KB=$((CACHE_FREED_KB + ${sz:-0}))
        find "$d" -mindepth 1 -delete 2>/dev/null
      fi
    done
    [ "$found" -eq 1 ] && break
  done
  if [ "$(cfg_get USE_ROOT 0)" = "1" ] && have_su; then
    su_run "rm -rf /data/data/$pkg/cache/* /data/data/$pkg/code_cache/*" >/dev/null 2>&1 && found=1
  fi
  CACHE_FOUND=$found
  if [ "$found" -eq 0 ]; then
    if ! ls "$first/Android/data" >/dev/null 2>&1; then
      why="อ่าน $first/Android/data ไม่ได้ (สิทธิ์ storage ถูกจำกัด)"
    elif [ ! -d "$first/Android/data/$pkg" ]; then
      why="ไม่มีโฟลเดอร์ข้อมูลภายนอกของแพ็กเกจนี้"
    else
      why="ไม่พบโฟลเดอร์ cache ภายนอก"
    fi
    log WARN "$pkg ข้ามล้างแคช: $why"
  fi
  return 0
}
force_stop() {
  am force-stop "$1" >/dev/null 2>&1
  if [ "$(cfg_get USE_ROOT 0)" = "1" ] && have_su; then
    su_run "am force-stop $1" >/dev/null 2>&1
  fi
  return 0
}
bad_out() { printf '%s' "$1" | grep -qiE 'error|exception|aborted|not found|unable to|denied|does not exist'; }
launch_deeplink() {
  local pkg="$1" uri="$2" out
  out=$(am start -a android.intent.action.VIEW -d "$uri" -p "$pkg" 2>&1)
  if bad_out "$out"; then
    log ERROR "$pkg เข้าเกมไม่สำเร็จ: $(trunc "$out" 200)"
    return 1
  fi
  if printf '%s' "$out" | grep -qi 'warning'; then log WARN "$pkg: $(trunc "$out" 160)"; fi
  return 0
}
launch_app() {
  local pkg="$1" act o1 o2 o3
  o1=$(am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p "$pkg" 2>&1)
  bad_out "$o1" || return 0
  act=$(/system/bin/cmd package resolve-activity --brief -a android.intent.action.MAIN \
        -c android.intent.category.LAUNCHER -p "$pkg" 2>/dev/null | tail -n 1)
  case "$act" in
    */*) o2=$(am start -n "$act" 2>&1); bad_out "$o2" || return 0 ;;
    *)   o2="ไม่พบ activity หลัก" ;;
  esac
  if [ -x /system/bin/monkey ]; then
    o3=$(/system/bin/monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 2>&1)
    bad_out "$o3" || return 0
  else
    o3="ไม่มี /system/bin/monkey"
  fi
  log ERROR "$pkg เปิดไม่สำเร็จ | am: $(trunc "$o1" 100) | resolve: $(trunc "$o2" 70) | monkey: $(trunc "$o3" 70)"
  return 1
}
set_state() { printf '%s|%s|%s' "$2" "$(date '+%H:%M:%S')" "$3" > "$STATE/$1"; }
process_pkg() {
  local pkg="$1" uri="$2" n="$3" t="$4" rc mb
  printf '\n%s[%s/%s]%s %s\n' "$C" "$n" "$t" "$N" "$pkg"
  if [ -n "$uri" ]; then printf '%s' "$uri" > "$STATE/uri.$pkg"; else rm -f "$STATE/uri.$pkg"; fi
  force_stop "$pkg"; sleep 1
  if [ "$(cfg_get AUTO_CLEAR 1)" = "1" ]; then
    clear_cache "$pkg"
    if [ "$CACHE_FOUND" -eq 1 ]; then
      mb=$(fmt_mb "$CACHE_FREED_KB")
      printf '   🧹 ล้างแคชภายนอกแล้ว %s MB\n' "$mb"
      log INFO "$pkg ล้างแคชภายนอก ${mb}MB"
    else
      printf '   🧹 ข้ามล้างแคช (ดู Log ได้)\n'
    fi
  fi
  if [ "$(cfg_get COOKIE_AUTOLOGIN 1)" = "1" ] && [ -s "$CFG/cookie.$pkg" ]; then
    if cookie_inject "$pkg" "$(cat "$CFG/cookie.$pkg")"; then
      printf '   🔑 ล็อกอินด้วยคุกกี้แล้ว (%s)\n' "$(cfg_get "uname.$pkg" "?")"
      log INFO "$pkg ล็อกอินด้วยคุกกี้"
    else
      printf '   %s⚠ ล็อกอินด้วยคุกกี้ไม่สำเร็จ: %s%s\n' "$Y" "$CK_ERR" "$N"
      log WARN "$pkg ล็อกอินด้วยคุกกี้ไม่สำเร็จ: $CK_ERR"
    fi
  fi
  if [ "$(cfg_get AUTOEXEC_ON 1)" = "1" ] && ae_has_scripts; then
    if ae_sync_pkg "$pkg"; then
      printf '   📜 วางสคริปต์ Auto Execute แล้ว %s ไฟล์\n' "$AE_COUNT"
    else
      printf '   %s⚠ Auto Execute: %s%s\n' "$Y" "$AE_ERR" "$N"
      log WARN "$pkg autoexec: $AE_ERR"
    fi
  fi
  if [ "$(cfg_get PERF_MODE 0)" = "1" ]; then
    if perf_apply_cfg "$pkg"; then
      printf '   ⚡ โหมดประหยัดสเปก: %s\n' "$PERF_MSG"
    else
      printf '   %s⚠ โหมดประหยัดสเปก: %s%s\n' "$Y" "$PERF_ERR" "$N"
      log WARN "$pkg perf: $PERF_ERR"
    fi
  fi
  if [ -n "$uri" ]; then
    printf '   🚀 เข้าเกม [โหมด %s]\n' "$(launch_mode)"
    launch_smart "$pkg" "$uri"; rc=$?
  else
    printf '   🚀 เปิดแอป [โหมด %s]\n' "$(launch_mode)"
    launch_smart "$pkg" ""; rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    printf '   %s✓ ส่งคำสั่งสำเร็จ%s\n' "$G" "$N"
    set_state "$pkg" OK "${uri:-open}"
    stat_set "$pkg" start "$(date +%s)"; stat_inc "$pkg" launch_ok
    log INFO "$pkg ส่งคำสั่งสำเร็จ (${uri:-open})"
  else
    printf '   %s✗ ล้มเหลว (ดู Log)%s\n' "$R" "$N"
    set_state "$pkg" FAIL "${uri:-open}"
    stat_inc "$pkg" launch_fail
  fi
  return "$rc"
}
run_batch() {
  local label="$1" i total ok=0 fail=0 delay pkg done_count=0
  total=0; delay=$(cfg_get LAUNCH_DELAY 20)
  for pkg in "${PKGS[@]}"; do
    [ "$(screen_enabled "$pkg")" = "1" ] && total=$((total+1))
  done
  if [ "$total" -eq 0 ]; then
    printf '%sไม่มีจอที่เปิดใช้งานในตัวจัดการ%s\n' "$Y" "$N"
    return 0
  fi
  log INFO "=== เริ่ม: $label | จอที่เปิดใช้งาน $total ==="
  for i in "${!PKGS[@]}"; do
    pkg="${PKGS[$i]}"
    if [ "$(screen_enabled "$pkg")" != "1" ]; then
      printf '\n%s[ข้าม]%s %s (ปิดใช้งานในตัวจัดการ)\n' "$Y" "$N" "$pkg"
      continue
    fi
    done_count=$((done_count+1))
    if process_pkg "$pkg" "${URIS[$i]:-}" "$done_count" "$total"; then ok=$((ok+1)); else fail=$((fail+1)); fi
    if [ "$done_count" -lt "$total" ]; then
      printf '   ⏳ รอ %s วิ ก่อนจอถัดไป...\n' "$delay"
      sleep "$delay"
    fi
  done
  log INFO "=== จบ: $label | สำเร็จ=$ok ล้มเหลว=$fail ==="
  printf '\n%sสรุป: ส่งคำสั่งสำเร็จ %s / ล้มเหลว %s%s\n' "$Y" "$ok" "$fail" "$N"
  if [ -n "$(cfg_get WEBHOOK_URL)" ]; then
    printf '📡 ส่ง Webhook...'
    if send_status "$label" "$ok" "$fail"; then printf ' สำเร็จ\n'; else printf ' ล้มเหลว (ดู Log)\n'; fi
  fi
}
json_escape() { printf '%s' "$1" | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\t/\\t/g;s/\r//g;s/\n/\\n/g'; }
send_webhook() {
  local url t b color="${3:-3066993}" payload code
  url=$(cfg_get WEBHOOK_URL)
  [ -z "$url" ] && return 2
  t=$(json_escape "$1"); b=$(json_escape "$2")
  payload=$(printf '{"username":"PROCYSIS","embeds":[{"title":"%s","description":"%s","color":%s,"footer":{"text":"PROCYSIS • %s"}}]}' "$t" "$b" "$color" "$(date '+%F %T')")
  code=$(curl -s -o /dev/null -m 20 -w '%{http_code}' -H 'Content-Type: application/json' -d "$payload" "$url" 2>/dev/null)
  case "$code" in
    200|204) log INFO "ส่ง Webhook สำเร็จ ($1)"; return 0 ;;
    *) log ERROR "ส่ง Webhook ไม่สำเร็จ HTTP=${code:-ไม่มีการตอบกลับ}"; return 1 ;;
  esac
}
build_report() {
  local model ver mt ma load up pkg st s t u run icon err now rj hr lr tot_rj=0 tot_hr=0 nm tot_rb=0
  now=$(date +%s)
  model=$(getprop ro.product.model 2>/dev/null)
  ver=$(getprop ro.build.version.release 2>/dev/null)
  mt=$(awk '/^MemTotal/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null)
  ma=$(awk '/^MemAvailable/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null)
  load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)
  up=$(awk '{printf "%dh %dm",int($1/3600),int(($1%3600)/60)}' /proc/uptime 2>/dev/null)
  printf '📱 %s | Android %s\n' "${model:-?}" "${ver:-?}"
  printf '🧠 RAM ว่าง %s / %s MB\n' "${ma:-?}" "${mt:-?}"
  printf '⚙️ Load %s | Uptime เครื่อง %s\n' "${load:-?}" "${up:-?}"
  printf '🖥 จอที่เปิดใช้งาน %s / %s\n\n' "$(count_enabled)" "${#PKGS[@]}"
  for pkg in "${PKGS[@]}"; do
    if [ "$(screen_enabled "$pkg")" != "1" ]; then printf '⚫ %s (ปิดใช้งานในตัวจัดการ)\n' "$pkg"; continue; fi
    st=$(cat "$STATE/$pkg" 2>/dev/null)
    IFS='|' read -r s t u <<< "$st"
    case "$s" in OK) icon="✅" ;; FAIL) icon="❌" ;; STOP) icon="⏹️" ;; *) icon="➖" ;; esac
    run=$(alive_mark "$pkg")
    rj=$(stat_get "$pkg" rejoins 0); hr=$(rejoin_count_hr "$pkg")
    tot_rj=$((tot_rj + rj)); tot_hr=$((tot_hr + hr))
    nm=$(cfg_get "uname.$pkg" "")
    printf '%s %s %s (สั่งเปิด %s)%s\n' "$run" "$icon" "$pkg" "${t:--}" "${nm:+ 👤 $nm}"
    if [ "$run" = "🟢" ]; then up=$(pkg_uptime "$pkg"); else up="-"; fi
    printf '   ⏱ รันมา %s | 🔁 รีจอย %s ครั้ง (ชม.ล่าสุด %s)\n' "$up" "$rj" "$hr"
    if [ "$rj" -gt 0 ]; then
      lr=$(stat_get "$pkg" last_rejoin 0)
      printf '   ↳ ล่าสุดเมื่อ %s ที่แล้ว: %s\n' "$(fmt_dur $((now - lr)))" "$(stat_get "$pkg" last_reason -)"
    fi
    [ "${W_CAPPED[$pkg]:-0}" = "1" ] && printf '   ⛔ รีจอยครบเพดาน/ชม. หยุดจอนี้ชั่วคราว\n'
    [ "${W_BADCK[$pkg]:-0}" = "1" ] && printf '   🔑 คุกกี้ใช้ไม่ได้/หมดอายุ ต้องใส่ใหม่\n'
    if has_robux "$pkg"; then
      printf '   %s\n' "$(acct_summary "$pkg")"
      tot_rb=$((tot_rb + $(stat_get "$pkg" robux 0)))
    fi
    case "$(stat_get "$pkg" acct_state unknown)" in
      banned)  printf '   🚫 บัญชีถูกแบน\n' ;;
      expired) [ "${W_BADCK[$pkg]:-0}" = "1" ] || printf '   🔑 คุกกี้หมดอายุ/ออกจากระบบ ต้องใส่ใหม่\n' ;;
    esac
  done
  [ "$tot_rb" -gt 0 ] && printf '\n💰 Robux รวมทุกบัญชี R$ %s\n' "$(fmt_num "$tot_rb")"
  printf '\n🔁 รีจอยรวมทุกจอ %s ครั้ง (ชม.ล่าสุด %s)\n' "$tot_rj" "$tot_hr"
  err=$(grep -E '\[(ERROR|WARN)\]' "$LOG_FILE" | tail -n 3)
  [ -n "$err" ] && printf '\n🐞 บัคล่าสุด:\n%s\n' "$err"
  printf '\n🟢อยู่ 🔴ไม่พบ ⏳เพิ่งเปิด ❔ตรวจไม่ได้ ⚪ไม่ทราบ'
}
send_status() {
  local title="${1:-สถานะ}" ok="$2" fail="$3" color=3066993 body
  [ -z "$(cfg_get WEBHOOK_URL)" ] && return 2
  [ "${#PKGS[@]}" -eq 0 ] && mapfile -t PKGS < <(detect_pkgs)
  if [ -n "$fail" ] && [ "$fail" -gt 0 ]; then color=15158332; fi
  body=$(build_report "$ok" "$fail")
  while [ "$(utf8_len "$body")" -gt 3900 ] && [[ "$body" == *$'\n'* ]]; do body="${body%$'\n'*}"; done
  send_webhook "PROCYSIS • $title" "$body" "$color"
}
api_get() {
  local url="$1" try out code
  for try in 1 2 3 4; do
    out=$(curl -s -m 20 -A "$JOIN_UA" -w $'\n%{http_code}' "$url" 2>/dev/null)
    code="${out##*$'\n'}"
    out="${out%$'\n'*}"
    case "$code" in
      200) printf '%s' "$out"; return 0 ;;
      429) log WARN "API 429 (ถูกจำกัดความถี่) รอแล้วลองใหม่ ครั้งที่ $try"; sleep $((try * 4)) ;;
      *)   log ERROR "API HTTP=${code:-ไม่มีการตอบกลับ} ${url:0:90}"; return 1 ;;
    esac
  done
  return 1
}
urlenc_cursor() { printf '%s' "$1" | sed -e 's/+/%2B/g' -e 's#/#%2F#g' -e 's/=/%3D/g'; }
find_server() {
  local place="$1" raw="${2,,}" pre suf maxp order cursor page url body nxt line id plain pl mx
  local p_id="" p_pl=-1 p_mx=0 f_id="" f_pl=-1 f_mx=0
  FOUND_ID=""; FOUND_PLAYING=-1; FOUND_MAX=0; FOUND_NOTE=""
  raw="${raw// /}"
  if [[ "$raw" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    FOUND_ID="$raw"; FOUND_NOTE="uuid-เต็ม"; return 0
  fi
  [[ "$raw" =~ ^[0-9a-f]{4}-[0-9a-f]{4}$ ]] || return 2
  [[ "$place" =~ ^[0-9]+$ ]] || return 3
  pre="${raw%-*}"; suf="${raw#*-}"
  maxp=$(cfg_get JOIN_MAX_PAGES 15)
  case "$maxp" in ''|*[!0-9]*) maxp=15 ;; esac
  for order in Desc Asc; do
    cursor=""; page=0
    while [ "$page" -lt "$maxp" ]; do
      page=$((page + 1))
      url="https://games.roblox.com/v1/games/$place/servers/Public?sortOrder=$order&excludeFullGames=false&limit=100"
      [ -n "$cursor" ] && url="$url&cursor=$(urlenc_cursor "$cursor")"
      printf '   🔎 สแกนเซิร์ฟ (%s) หน้า %s/%s ...\r' "$order" "$page" "$maxp" >&2
      body=$(api_get "$url") || break
      while IFS= read -r line; do
        id=$(grep -oE '"id":"[0-9a-f-]{36}"' <<<"$line" | head -n1 | cut -d'"' -f4)
        [ -z "$id" ] && continue
        plain="${id//-/}"
        pl=$(grep -oE '"playing":[0-9]+' <<<"$line" | head -n1 | cut -d: -f2)
        mx=$(grep -oE '"maxPlayers":[0-9]+' <<<"$line" | head -n1 | cut -d: -f2)
        if [[ "$plain" == "$pre"* && "$plain" == *"$suf" ]]; then
          p_id="$id"; p_pl="${pl:--1}"; p_mx="${mx:-0}"
          break 3
        fi
        if [ -z "$f_id" ] && [[ "$plain" == *"$pre"* && "$plain" == *"$suf"* ]]; then
          f_id="$id"; f_pl="${pl:--1}"; f_mx="${mx:-0}"
        fi
      done < <(sed 's/{"id":"/\n{"id":"/g' <<<"$body" | grep '^{"id":"')
      nxt=$(grep -oE '"nextPageCursor":"[^"]+"' <<<"$body" | head -n1 | cut -d'"' -f4)
      [ -z "$nxt" ] && break
      cursor="$nxt"
      sleep 1
    done
  done
  printf '\033[2K\r' >&2
  if [ -n "$p_id" ]; then
    FOUND_ID="$p_id"; FOUND_PLAYING="$p_pl"; FOUND_MAX="$p_mx"; FOUND_NOTE="ตรงหน้า+ท้าย"
    log INFO "พบเซิร์ฟ $raw -> $FOUND_ID ($FOUND_PLAYING/$FOUND_MAX)"
    return 0
  fi
  if [ -n "$f_id" ]; then
    FOUND_ID="$f_id"; FOUND_PLAYING="$f_pl"; FOUND_MAX="$f_mx"; FOUND_NOTE="ตรงบางส่วน"
    log WARN "เซิร์ฟ $raw ตรงแบบสำรอง -> $FOUND_ID"
    return 0
  fi
  log WARN "ไม่พบเซิร์ฟรหัส $raw ใน place $place (สแกน $maxp หน้า x2 ทิศทาง)"
  return 1
}
user_to_id() {
  local in="${1//$'\r'/}" body uid
  in="${in// /}"
  [ -z "$in" ] && return 1
  case "$in" in
    */users/*) in="${in##*/users/}"; in="${in%%/*}" ;;
  esac
  if [[ "$in" =~ ^[0-9]+$ ]]; then printf '%s' "$in"; return 0; fi
  [[ "$in" =~ ^[A-Za-z0-9_]{3,20}$ ]] || return 1
  body=$(curl -s -m 15 -A "$JOIN_UA" -H 'Content-Type: application/json' \
    -d "{\"usernames\":[\"$in\"],\"excludeBannedUsers\":true}" \
    https://users.roblox.com/v1/usernames/users 2>/dev/null)
  uid=$(grep -oE '"id":[0-9]+' <<<"$body" | head -n1 | cut -d: -f2)
  [ -n "$uid" ] || return 1
  printf '%s' "$uid"
}
get_presence() {
  local uid="$1" ck="${2:-$(cfg_get ROBLOSECURITY)}" hdr ckh="" body tok
  local -a extra=()
  PRES_TYPE=-1; PRES_PLACE=""; PRES_ROOT=""; PRES_GAME=""; PRES_HTTP=""
  if [ -n "$ck" ]; then
    ckh=$(ck_hdr "$ck") || return 1
    extra=(-H @"$ckh")
  fi
  hdr=$(mktemp "$BASE/.hdr.XXXXXX") || { [ -n "$ckh" ] && rm -f "$ckh"; return 1; }
  body=$(curl -s -m 20 -D "$hdr" -X POST "${extra[@]}" -A "$JOIN_UA" \
    -H 'Content-Type: application/json' -d "{\"userIds\":[$uid]}" \
    https://presence.roblox.com/v1/presence/users 2>/dev/null)
  if ! grep -q 'userPresences' <<<"$body"; then
    tok=$(tr -d '\r' < "$hdr" | awk -F': ' 'tolower($1)=="x-csrf-token"{print $2; exit}')
    if [ -n "$tok" ]; then
      : > "$hdr"
      body=$(curl -s -m 20 -D "$hdr" -X POST "${extra[@]}" -A "$JOIN_UA" -H "x-csrf-token: $tok" \
        -H 'Content-Type: application/json' -d "{\"userIds\":[$uid]}" \
        https://presence.roblox.com/v1/presence/users 2>/dev/null)
    fi
  fi
  PRES_HTTP=$(head -n 1 "$hdr" | grep -oE ' [0-9]{3}' | head -n 1 | tr -d ' ')
  rm -f "$hdr"
  [ -n "$ckh" ] && rm -f "$ckh"
  if ! grep -q 'userPresences' <<<"$body"; then
    log ERROR "presence ตอบกลับผิดปกติ (HTTP ${PRES_HTTP:-?}): $(trunc "$body" 100)"
    return 1
  fi
  PRES_TYPE=$(grep -oE '"userPresenceType":[0-9]+' <<<"$body" | head -n 1 | cut -d: -f2)
  PRES_PLACE=$(grep -oE '"placeId":[0-9]+' <<<"$body" | head -n 1 | cut -d: -f2)
  PRES_ROOT=$(grep -oE '"rootPlaceId":[0-9]+' <<<"$body" | head -n 1 | cut -d: -f2)
  PRES_GAME=$(grep -oE '"gameId":"[0-9a-f-]{36}"' <<<"$body" | head -n 1 | cut -d'"' -f4)
  [ -z "$PRES_PLACE" ] && PRES_PLACE="$PRES_ROOT"
  [ -z "$PRES_TYPE" ] && PRES_TYPE=-1
  return 0
}
build_instance_uri() { printf 'roblox://placeId=%s&gameInstanceId=%s' "$1" "$2"; }
count_enabled() {
  local p n=0
  for p in "${PKGS[@]}"; do [ "$(screen_enabled "$p")" = "1" ] && n=$((n + 1)); done
  printf '%s' "$n"
}
confirm() {
  local a
  printf '%s [y/N] : ' "$1"
  read -r a
  [[ "$a" == [yY] ]]
}
fill_uris() { local p; URIS=(); for p in "${PKGS[@]}"; do URIS+=("$1"); done; }
menu_join_code() {
  local place code uri n free rc
  banner; load_pkgs || return
  echo
  ask "Game ID (หรือวางลิงก์เกม)" "$(cfg_get PLACE_ID)"; place=$(norm_place "$REPLY_VAL")
  ask "รหัสเซิร์ฟ (เช่น 4b26-4319)" "$(cfg_get LAST_SRV_CODE)"; code="$REPLY_VAL"
  code="${code,,}"; code="${code// /}"
  if [ -z "$place" ]; then
    printf '%s✗ Game ID ไม่ถูกต้อง%s\n' "$R" "$N"; pause; return
  fi
  printf '\n'
  find_server "$place" "$code"; rc=$?
  case "$rc" in
    2) printf '%s✗ รูปแบบรหัสไม่ถูกต้อง (ต้องเป็น xxxx-xxxx เลขฐาน 16)%s\n' "$R" "$N"; pause; return ;;
    3) printf '%s✗ Game ID ไม่ถูกต้อง%s\n' "$R" "$N"; pause; return ;;
    1) printf '%s✗ ไม่พบเซิร์ฟรหัสนี้%s\n' "$R" "$N"
       printf '%s  - เซิร์ฟอาจปิดไปแล้ว / เป็น VIP (ไม่อยู่ในลิสต์สาธารณะ)\n  - ตรวจว่า Game ID ตรงกับเกมที่เพื่อนอยู่\n  - เพิ่มจำนวนหน้าสแกนได้ในเมนูย่อย ข้อ 4%s\n' "$DIM" "$N"
       pause; return ;;
  esac
  printf '%s✓ พบเซิร์ฟ%s (%s)\n' "$G" "$N" "$FOUND_NOTE"
  printf '   ID เต็ม : %s\n' "$FOUND_ID"
  if [ "$FOUND_PLAYING" -ge 0 ] && [ "$FOUND_MAX" -gt 0 ]; then
    free=$((FOUND_MAX - FOUND_PLAYING))
    n=$(count_enabled)
    printf '   ผู้เล่น : %s/%s (ว่าง %s ที่)\n' "$FOUND_PLAYING" "$FOUND_MAX" "$free"
    if [ "$n" -gt "$free" ]; then
      printf '%s⚠ จอที่เปิดใช้งาน %s จอ แต่ที่ว่างมี %s - บางจออาจเข้าไม่ได้%s\n' "$Y" "$n" "$free" "$N"
      confirm "ดำเนินการต่อ?" || { pause; return; }
    fi
  fi
  uri=$(valid_uri "$(build_instance_uri "$place" "$FOUND_ID")")
  if [ -z "$uri" ]; then
    printf '%s✗ สร้างลิงก์ไม่สำเร็จ%s\n' "$R" "$N"; pause; return
  fi
  cfg_set PLACE_ID "$place"; cfg_set LAST_SRV_CODE "$code"
  fill_uris "$uri"
  run_batch "เข้าเซิร์ฟรหัส $code"; pause
}
menu_join_friend() {
  local fin uid uri place hasck
  banner; load_pkgs || return
  echo
  ask "User ID / ชื่อ / ลิงก์โปรไฟล์ของเพื่อน" "$(cfg_get LAST_FRIEND)"; fin="$REPLY_VAL"
  uid=$(user_to_id "$fin")
  if [ -z "$uid" ]; then
    printf '%s✗ หา User ID ไม่เจอ (ตรวจการสะกด/อินเทอร์เน็ต)%s\n' "$R" "$N"
    log ERROR "user_to_id ล้มเหลว: $fin"; pause; return
  fi
  printf '   👤 User ID : %s\n' "$uid"
  hasck=$(cfg_get ROBLOSECURITY)
  printf '   📡 ตรวจสถานะ...\n'
  if ! get_presence "$uid"; then
    printf '%s✗ ดึงสถานะไม่ได้%s\n' "$R" "$N"
    [ -z "$hasck" ] && printf '%s  ต้องตั้งคุกกี้ก่อน (เมนูย่อย ข้อ 3) เพราะ Roblox ไม่ให้ดูสถานะแบบไม่ล็อกอิน%s\n' "$Y" "$N"
    pause; return
  fi
  case "$PRES_TYPE" in
    0) printf '%s✗ เพื่อนออฟไลน์%s\n' "$Y" "$N"; pause; return ;;
    1) printf '%s✗ เพื่อนออนไลน์แต่ไม่ได้อยู่ในเกม%s\n' "$Y" "$N"; pause; return ;;
    3) printf '%s✗ เพื่อนอยู่ใน Roblox Studio%s\n' "$Y" "$N"; pause; return ;;
    2) : ;;
    *) printf '%s✗ อ่านสถานะไม่ได้%s\n' "$R" "$N"; pause; return ;;
  esac
  place="$PRES_PLACE"
  if [ -z "$PRES_GAME" ] || [ -z "$place" ]; then
    printf '%s✗ เพื่อนอยู่ในเกม แต่ไม่ได้ข้อมูลเซิร์ฟ%s\n' "$Y" "$N"
    if [ -z "$hasck" ]; then
      printf '  ตั้งคุกกี้ (ข้อ 3) เพื่อดูเซิร์ฟของเพื่อน\n'
    else
      printf '  เพื่อนอาจปิดการเข้าร่วม หรือบัญชีที่ใช้คุกกี้ไม่ได้เป็นเพื่อนกัน\n'
    fi
    printf '  ทางเลือก: ใช้ข้อ 1 ด้วยรหัสเซิร์ฟจากหน้า Join Friends แทน\n'
    pause; return
  fi
  uri=$(valid_uri "$(build_instance_uri "$place" "$PRES_GAME")")
  [ -z "$uri" ] && { printf '%s✗ สร้างลิงก์ไม่สำเร็จ%s\n' "$R" "$N"; pause; return; }
  printf '%s✓ เจอเพื่อนในเกม%s\n   place : %s\n   server: %s\n' "$G" "$N" "$place" "$PRES_GAME"
  log INFO "ตามเพื่อน uid=$uid place=$place server=$PRES_GAME"
  cfg_set LAST_FRIEND "$fin"
  fill_uris "$uri"
  run_batch "ตามเพื่อน $uid"; pause
}
menu_join_cookie() {
  local v
  printf '\n%s⚠ แนะนำให้ใช้บัญชีรอง ห้ามส่งคุกกี้ให้ใคร%s\n' "$Y" "$N"
  printf 'วาง .ROBLOSECURITY (ไม่แสดงบนจอ | Enter=ยกเลิก | -=ลบ): '
  read -rs v; echo
  v="${v//$'\r'/}"
  case "$v" in
    '') return ;;
    -)  rm -f "$CFG/ROBLOSECURITY"; echo "ลบแล้ว"; log INFO "ลบคุกกี้"; sleep 1 ;;
    *)  v="${v#.ROBLOSECURITY=}"
        ( umask 077; printf '%s' "$v" > "$CFG/ROBLOSECURITY" )
        chmod 600 "$CFG/ROBLOSECURITY" 2>/dev/null
        echo "บันทึกแล้ว"; log INFO "ตั้งคุกกี้แล้ว"; sleep 1 ;;
  esac
}
menu_join_server() {
  local c ck v
  while true; do
    banner
    if [ -n "$(cfg_get ROBLOSECURITY)" ]; then ck="ตั้งค่าแล้ว"; else ck="ยังไม่ตั้งค่า"; fi
    printf '%sเข้าเซิร์ฟเฉพาะ / ตามเพื่อน%s\n\n' "$Y" "$N"
    printf ' 1) เข้าด้วยรหัสเซิร์ฟ (เช่น 4b26-4319 จากหน้า Join Friends)\n'
    printf ' 2) ตามเพื่อนด้วย User ID / ชื่อ / ลิงก์โปรไฟล์\n'
    printf ' 3) คุกกี้สำหรับดูเซิร์ฟเพื่อน : %s\n' "$ck"
    printf ' 4) จำนวนหน้าสแกนเซิร์ฟสูงสุด : %s (หน้าละ 100 เซิร์ฟ)\n' "$(cfg_get JOIN_MAX_PAGES 15)"
    printf ' 0) กลับ\n\n'
    read -rp "เลือก: " c || on_exit
    case "$c" in
      1) menu_join_code ;;
      2) menu_join_friend ;;
      3) menu_join_cookie ;;
      4) ask "กี่หน้า" "$(cfg_get JOIN_MAX_PAGES 15)"
         v="$REPLY_VAL"
         case "$v" in ''|*[!0-9]*|0) ;; *) cfg_set JOIN_MAX_PAGES "$v" ;; esac ;;
      0) return ;;
    esac
  done
}
declare -A W_MISS=() W_LAST=() W_GRACE=() W_WSTART=() W_WCOUNT=() W_CAPPED=()
saved_uri() { [ -s "$STATE/uri.$1" ] && cat "$STATE/uri.$1"; }
nap() { local i=0; while [ "$i" -lt "$1" ] && [ "$STOP" -eq 0 ]; do sleep 1; i=$((i + 1)); done; }
PS_MIN=30
PROC_SNAP=""; PROC_SRC="-"; PROC_BLIND=1; SNAP_N=0
snap_consider() {
  local n
  n=$(printf '%s\n' "$2" | grep -c .)
  if [ "$n" -gt "$SNAP_N" ]; then PROC_SNAP="$2"; PROC_SRC="$1"; SNAP_N=$n; fi
}
snapshot_procs() {
  local out p
  PROC_SNAP=""; PROC_SRC="-"; SNAP_N=0
  if { [ "$(cfg_get USE_ROOT 0)" = "1" ] && have_su; } || have_adb; then
    if elev_run 'ps -A' nocheck; then snap_consider "ps -A (su/adb)" "$ELEV_OUT"; fi
  fi
  out=$(ps -A -o NAME 2>/dev/null); snap_consider "ps -A -o NAME" "$out"
  out=$(ps -A 2>/dev/null);         snap_consider "ps -A" "$out"
  out=$(ps -e 2>/dev/null);         snap_consider "ps -e" "$out"
  out=$(ps 2>/dev/null);            snap_consider "ps" "$out"
  if [ "$SNAP_N" -lt "$PS_MIN" ]; then
    out=$(for p in /proc/[0-9]*; do { tr '\0' ' ' < "$p/cmdline"; echo; } 2>/dev/null; done)
    snap_consider "/proc/*/cmdline" "$out"
  fi
  if [ "$SNAP_N" -ge "$PS_MIN" ]; then PROC_BLIND=0; else PROC_BLIND=1; fi
}
proc_has() {
  local esc
  esc=$(printf '%s' "$1" | sed 's/\./\\./g')
  grep -Eq "(^|[^A-Za-z0-9_.])${esc}(\$|[^A-Za-z0-9_.])" <<<"$PROC_SNAP"
}
alive_proc() {
  proc_has "$1" && return 0
  [ "$PROC_BLIND" -eq 1 ] && return 2
  return 1
}
alive_dumpsys() {
  local out
  command -v dumpsys >/dev/null 2>&1 || return 2
  out=$(dumpsys activity processes 2>&1)
  case "$out" in ''|*"Permission Denial"*|*"Can't find service"*) return 2 ;; esac
  grep -qF ":$1/u" <<<"$out" && return 0
  return 1
}
alive_presence() {
  local uid
  uid=$(cfg_get "uid.$1")
  [ -n "$uid" ] || return 2
  get_presence "$uid" || return 2
  sleep 1
  case "$PRES_TYPE" in
    2) return 0 ;;
    0|1|3) return 1 ;;
    *) return 2 ;;
  esac
}
is_alive() {
  local pkg="$1" m rc
  m=$(cfg_get ALIVE_METHOD auto)
  case "$m" in
    proc)     alive_proc "$pkg"; return $? ;;
    dumpsys)  alive_dumpsys "$pkg"; return $? ;;
    cookie)   alive_cookie "$pkg"; return $? ;;
    presence) alive_presence "$pkg"; return $? ;;
  esac
  alive_proc "$pkg"; rc=$?;     [ "$rc" -ne 2 ] && return "$rc"
  alive_dumpsys "$pkg"; rc=$?;  [ "$rc" -ne 2 ] && return "$rc"
  alive_cookie "$pkg"; rc=$?;   [ "$rc" -ne 2 ] && return "$rc"
  alive_presence "$pkg"; return $?
}
notify_rejoin() {
  [ -n "$(cfg_get WEBHOOK_URL)" ] || return 0
  ( send_webhook "PROCYSIS • $1" "$2" "${3:-15105570}" >/dev/null 2>&1 & )
}
rejoin_screen() {
  local pkg="$1" why="$2" nocap="${3:-}" now uri cap
  now=$(date +%s)
  cap=$(cfg_get REJOIN_CAP 6)
  case "$cap" in ''|*[!0-9]*) cap=6 ;; esac
  if [ -z "$nocap" ]; then
    if [ $((now - ${W_WSTART[$pkg]:-0})) -ge 3600 ]; then
      W_WSTART[$pkg]=$now; W_WCOUNT[$pkg]=0; W_CAPPED[$pkg]=0
    fi
    if [ "$cap" -gt 0 ] && [ "${W_WCOUNT[$pkg]:-0}" -ge "$cap" ]; then
      if [ "${W_CAPPED[$pkg]:-0}" != "1" ]; then
        W_CAPPED[$pkg]=1
        log ERROR "$pkg รีจอยครบ $cap ครั้ง/ชม. หยุดรีจอยจอนี้ชั่วคราว"
        printf '\n%s⛔ %s รีจอยครบ %s ครั้ง/ชม. หยุดจอนี้ชั่วคราว%s\n' "$R" "$pkg" "$cap" "$N"
        notify_rejoin "⛔ $pkg" "รีจอยครบ $cap ครั้ง/ชั่วโมง หยุดจอนี้ชั่วคราว" 15158332
      fi
      return 1
    fi
    W_WCOUNT[$pkg]=$(( ${W_WCOUNT[$pkg]:-0} + 1 ))
  fi
  uri=$(saved_uri "$pkg")
  printf '\n%s🔁 รีจอย%s %s (%s)\n' "$Y" "$N" "$pkg" "$why"
  log WARN "รีจอย $pkg เหตุผล: $why | ลิงก์: ${uri:-open}"
  rejoin_note "$pkg" "$why"
  process_pkg "$pkg" "$uri" 1 1
  W_LAST[$pkg]=$(date +%s)
  W_GRACE[$pkg]=$(date +%s)
  notify_rejoin "🔁 $pkg" "เหตุผล: $why" 15105570
  return 0
}
watchdog_run() {
  local interval thr every delay grace pkg st now line idx en=0 blind=1 sym rep last_rep acct_every last_acct=0
  interval=$(cfg_get RJ_INTERVAL 45)
  thr=$(cfg_get RJ_THRESHOLD 2)
  every=$(cfg_get RJ_EVERY 0)
  delay=$(cfg_get LAUNCH_DELAY 20)
  grace=$(cfg_get RJ_GRACE 60)
  rep=$(cfg_get RJ_REPORT 0)
  case "$rep" in ''|*[!0-9]*) rep=0 ;; esac
  last_rep=$(date +%s)
  acct_every=$(cfg_get ACCT_EVERY 10)
  case "$acct_every" in ''|*[!0-9]*) acct_every=10 ;; esac
  mapfile -t PKGS < <(detect_pkgs)
  if [ -z "${PKGS[0]:-}" ]; then
    printf '%s✗ ไม่พบแพ็กเกจ%s\n' "$R" "$N"; pause; return
  fi
  now=$(date +%s)
  for pkg in "${PKGS[@]}"; do
    W_MISS[$pkg]=0; W_LAST[$pkg]=$now; W_GRACE[$pkg]=0
    [ "$(screen_enabled "$pkg")" = "1" ] && en=$((en + 1))
  done
  if [ "$en" -eq 0 ]; then
    printf '%sไม่มีจอที่เปิดใช้งานในตัวจัดการ%s\n' "$Y" "$N"; pause; return
  fi
  snapshot_procs
  for pkg in "${PKGS[@]}"; do
    is_alive "$pkg"; [ $? -ne 2 ] && blind=0
  done
  if [ "$blind" -eq 1 ]; then
    printf '%s⚠ เครื่องนี้ตรวจโปรเซสแอปอื่นไม่ได้ (ระบบซ่อน/ไม่มีสิทธิ์)%s\n' "$Y" "$N"
    if [ "$every" -le 0 ]; then
      printf '%s  ลองวิธี presence (ข้อ 9 + 8) หรือใช้ "รีจอยตามเวลา" (ข้อ 6) | ดูรายละเอียดที่ข้อ 3%s\n' "$DIM" "$N"
      pause; return
    fi
    printf '%s  จะใช้ได้เฉพาะรีจอยตามเวลาทุก %s นาที%s\n' "$DIM" "$every" "$N"
  fi
  STOP=0; trap 'STOP=1' INT
  printf '\n%s🛡 เริ่มเฝ้าจอ%s ตรวจทุก %s วิ | พลาด %s รอบ = รีจอย | ตามเวลา %s นาที (กด Ctrl+C เพื่อหยุด)\n' \
    "$G" "$N" "$interval" "$thr" "$every"
  log INFO "เริ่ม Auto Rejoin interval=$interval thr=$thr every=$every"
  notify_rejoin "🛡 เริ่มเฝ้าจอ" "จอที่เปิดใช้งาน $en | ตรวจทุก ${interval}s" 3066993
  while [ "$STOP" -eq 0 ]; do
    snapshot_procs
    line=""; idx=0
    for pkg in "${PKGS[@]}"; do
      idx=$((idx + 1))
      [ "$STOP" -eq 1 ] && break
      [ "$(screen_enabled "$pkg")" = "1" ] || continue
      now=$(date +%s)
      if [ $((now - ${W_GRACE[$pkg]:-0})) -lt "$grace" ]; then
        line="$line จอ$idx:⏳"
        printf 'G|0|%s' "$now" > "$STATE/alive.$pkg"
        continue
      fi
      is_alive "$pkg"; st=$?
      case "$st" in
        0) W_MISS[$pkg]=0; sym="🟢" ;;
        1) W_MISS[$pkg]=$(( ${W_MISS[$pkg]:-0} + 1 )); sym="🔴${W_MISS[$pkg]}" ;;
        *) sym="❔" ;;
      esac
      [ "${W_BADCK[$pkg]:-0}" = "1" ] && sym="$sym🔑✗"
      line="$line จอ$idx:$sym"
      printf '%s|%s|%s' "$st" "${W_MISS[$pkg]:-0}" "$now" > "$STATE/alive.$pkg"
      if [ "$st" -eq 1 ] && [ "${W_MISS[$pkg]}" -ge "$thr" ]; then
        if rejoin_screen "$pkg" "ไม่พบโปรเซส ${W_MISS[$pkg]} รอบติด"; then nap "$delay"; fi
        W_MISS[$pkg]=0
        continue
      fi
      if [ "$every" -gt 0 ] && [ $((now - ${W_LAST[$pkg]:-$now})) -ge $((every * 60)) ]; then
        rejoin_screen "$pkg" "รีจอยตามเวลา ทุก $every นาที" nocap && nap "$delay"
      fi
    done
    [ "$STOP" -eq 0 ] && printf '[%s]%s\n' "$(date +%T)" "$line"
    if [ "$rep" -gt 0 ] && [ "$STOP" -eq 0 ] && [ $(( $(date +%s) - last_rep )) -ge $((rep * 60)) ]; then
      last_rep=$(date +%s)
      if [ -n "$(cfg_get WEBHOOK_URL)" ]; then ( send_status "รายงานรอบ" "" "" >/dev/null 2>&1 & ); fi
    fi
    if [ "$acct_every" -gt 0 ] && [ "$STOP" -eq 0 ] && [ $(( $(date +%s) - last_acct )) -ge $((acct_every * 60)) ]; then
      last_acct=$(date +%s)
      acct_check_all quiet
    fi
    nap "$interval"
  done
  trap on_int INT
  rm -f "$STATE"/alive.* 2>/dev/null
  log INFO "หยุด Auto Rejoin"
  notify_rejoin "⏹ หยุดเฝ้าจอ" "ผู้ใช้หยุดระบบ" 9807270
  printf '\n%sหยุดเฝ้าจอแล้ว%s\n' "$Y" "$N"
  pause
}
rejoin_diag() {
  local p u r1 r2 r3 hasck
  banner; load_pkgs || return
  snapshot_procs
  hasck="ไม่มี"; [ -n "$(cfg_get ROBLOSECURITY)" ] && hasck="ตั้งแล้ว"
  printf '\n%sข้อมูลระบบ%s\n' "$C" "$N"
  printf ' uid ผู้ใช้: %s | su: %s | คุกกี้: %s\n' "$(id -u 2>/dev/null)" "$(have_su && echo มี || echo ไม่มี)" "$hasck"
  printf ' วิธีดูโปรเซสที่ดีที่สุด: %s (เห็น %s บรรทัด ต้อง >= %s)\n' "$PROC_SRC" "$SNAP_N" "$PS_MIN"
  if [ "$PROC_BLIND" -eq 1 ]; then
    printf ' %s→ มองไม่เห็นโปรเซสแอปอื่น (ระบบซ่อน) ใช้วิธี proc ไม่ได้%s\n' "$Y" "$N"
  else
    printf ' %s→ มองเห็นโปรเซสแอปอื่นได้%s\n' "$G" "$N"
  fi
  printf ' dumpsys: %s\n' "$(dumpsys activity processes 2>&1 | head -n 1 | cut -c1-70)"
  printf '\n%sผลต่อจอ%s (0=พบ/อยู่ในเกม 1=ไม่พบ 2=ตรวจไม่ได้)\n' "$C" "$N"
  for p in "${PKGS[@]}"; do
    u=$(saved_uri "$p")
    alive_proc "$p"; r1=$?
    alive_dumpsys "$p"; r2=$?
    alive_presence "$p"; r3=$?
    printf '\n%s%s%s\n   ลิงก์ : %s\n   User ID: %s\n   proc=%s  dumpsys=%s  presence=%s\n' \
      "$Y" "$p" "$N" "${u:-(เปิดแอปเฉยๆ)}" "$(cfg_get "uid.$p" "-")" "$r1" "$r2" "$r3"
  done
  printf '\n%sวิธีทดสอบ: เปิดเกมค้างไว้ก่อน แล้วดูว่าวิธีไหนได้ 0 กับจอที่กำลังเล่นอยู่%s\n' "$DIM" "$N"
  printf '%sถ้า proc/dumpsys ได้ 2 หมด → ตั้ง User ID ต่อจอ (ข้อ 9) + คุกกี้ แล้วใช้วิธี presence%s\n' "$DIM" "$N"
  printf '%sถ้าไม่มีวิธีไหนได้ → ใช้ "รีจอยตามเวลา" (ข้อ 6)%s\n' "$DIM" "$N"
  pause
}
rejoin_set_uids() {
  local p v id
  banner; load_pkgs || return
  printf '\n%sตั้ง User ID ของบัญชีที่ล็อกอินในแต่ละจอ (ใช้กับวิธี presence)%s\n' "$C" "$N"
  printf '%sใส่ User ID / ชื่อ / ลิงก์โปรไฟล์ | พิมพ์ - เพื่อลบ | ต้องตั้งคุกกี้ที่เมนู 8 ข้อ 3 ด้วย%s\n' "$DIM" "$N"
  for p in "${PKGS[@]}"; do
    printf '\n%s📦 %s%s\n' "$Y" "$p" "$N"
    ask "  User ID / ชื่อ" "$(cfg_get "uid.$p")"
    v="$REPLY_VAL"
    if [ -z "$v" ]; then rm -f "$CFG/uid.$p"; continue; fi
    id=$(user_to_id "$v")
    if [ -n "$id" ]; then cfg_set "uid.$p" "$id"; printf '  %s✓ %s%s\n' "$G" "$id" "$N"
    else printf '  %s✗ หา User ID ไม่เจอ%s\n' "$R" "$N"; fi
  done
  pause
}
rejoin_start_fresh() {
  local p
  banner; load_pkgs || return
  URIS=()
  for p in "${PKGS[@]}"; do URIS+=("$(saved_uri "$p")"); done
  run_batch "เปิดด้วยลิงก์ล่าสุด"
  watchdog_run
}
set_num() { # คีย์ ข้อความ ค่าเริ่มต้น ค่าต่ำสุด
  ask "$2" "$(cfg_get "$1" "$3")"
  case "$REPLY_VAL" in ''|*[!0-9]*) return ;; esac
  [ "$REPLY_VAL" -ge "$4" ] && cfg_set "$1" "$REPLY_VAL"
}
menu_rejoin() {
  local c m
  while true; do
    banner
    printf '%sAuto Rejoin (เฝ้าจอ + เข้าเกมใหม่อัตโนมัติ)%s\n\n' "$Y" "$N"
    printf ' 1) เริ่มเฝ้าจอ (ใช้ลิงก์ล่าสุดของแต่ละจอ)\n'
    printf ' 2) เปิดทุกจอด้วยลิงก์ล่าสุดก่อน แล้วเริ่มเฝ้า\n'
    printf ' 3) ดูลิงก์ล่าสุด / ทดสอบการตรวจจับ\n'
    printf ' 4) ตรวจทุก : %s วิ\n' "$(cfg_get RJ_INTERVAL 45)"
    printf ' 5) ไม่พบติดกัน : %s รอบ ถึงรีจอย\n' "$(cfg_get RJ_THRESHOLD 2)"
    printf ' 6) รีจอยตามเวลาทุก : %s นาที (0=ปิด)\n' "$(cfg_get RJ_EVERY 0)"
    printf ' 7) จำกัดรีจอย : %s ครั้ง/ชม./จอ (0=ไม่จำกัด)\n' "$(cfg_get REJOIN_CAP 6)"
    printf ' 8) วิธีตรวจจับ : %s (auto/proc/dumpsys/presence/cookie)\n' "$(cfg_get ALIVE_METHOD auto)"
    printf ' 9) ตั้ง User ID ต่อจอ (สำหรับวิธี presence)\n'
    printf '10) เวลารอหลังเปิดแอปก่อนเริ่มตรวจ : %s วิ (presence แนะนำ 150)\n' "$(cfg_get RJ_GRACE 60)"
    printf ' 0) กลับ\n\n'
    printf '%sลิงก์ล่าสุดจะถูกจำเมื่อเข้าเกมผ่านเมนู 1/2/8%s\n\n' "$DIM" "$N"
    read -rp "เลือก: " c || on_exit
    case "$c" in
      1) banner; load_pkgs && watchdog_run ;;
      2) rejoin_start_fresh ;;
      3) rejoin_diag ;;
      4) set_num RJ_INTERVAL "ตรวจทุกกี่วินาที" 45 10 ;;
      5) set_num RJ_THRESHOLD "พลาดกี่รอบติดถึงรีจอย" 2 1 ;;
      6) set_num RJ_EVERY "รีจอยตามเวลาทุกกี่นาที (0=ปิด)" 0 0 ;;
      7) set_num REJOIN_CAP "จำกัดกี่ครั้ง/ชม./จอ (0=ไม่จำกัด)" 6 0 ;;
      8) ask "วิธีตรวจจับ (auto/proc/dumpsys/presence/cookie)" "$(cfg_get ALIVE_METHOD auto)"
         m="$REPLY_VAL"
         case "$m" in auto|proc|dumpsys|presence|cookie) cfg_set ALIVE_METHOD "$m" ;; esac ;;
      9) rejoin_set_uids ;;
      10) set_num RJ_GRACE "รอกี่วินาทีหลังเปิดแอป" 60 20 ;;
      0) return ;;
    esac
  done
}
SLOT_I=0; SLOT_N=1; PRIV_OUT=""
ELEV_OUT=""
find_su() {
  local p
  if [ -n "$SU_BIN_OVERRIDE" ] && [ -x "$SU_BIN_OVERRIDE" ]; then printf '%s' "$SU_BIN_OVERRIDE"; return 0; fi
  p=$(command -v su 2>/dev/null)
  if [ -n "$p" ]; then printf '%s' "$p"; return 0; fi
  for p in /system/bin/su /system/xbin/su /sbin/su /su/bin/su /debug_ramdisk/su \
           /data/adb/magisk/su /apex/com.android.runtime/bin/su /vendor/bin/su; do
    if [ -x "$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 1
}
have_su() { [ -n "$(find_su)" ]; }
have_adb() { [ -n "$(cfg_get ADB_SERIAL)" ] && command -v adb >/dev/null 2>&1; }
adb_run() {
  local out rc s
  s=$(cfg_get ADB_SERIAL)
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout -k 3 "${SU_TIMEOUT:-20}" adb -s "$s" shell "$1" </dev/null 2>&1); rc=$?
  else
    out=$(adb -s "$s" shell "$1" </dev/null 2>&1); rc=$?
  fi
  stty sane 2>/dev/null
  printf '%s' "$out"
  return "$rc"
}
elev_bad() { grep -qiE 'permission denial|securityexception|exception|error:|usage:|not allowed|unauthorized|offline|no devices|cannot connect' <<<"$1"; }
elev_run() {
  local out rc errs=""
  ELEV_OUT=""
  if [ "$(cfg_get USE_ROOT 0)" = "1" ] && have_su; then
    out=$(su_run "$1"); rc=$?
    if [ "$rc" -eq 0 ] && { [ -n "$2" ] || ! elev_bad "$out"; }; then ELEV_OUT="$out"; return 0; fi
    errs="su: $out"
  fi
  if have_adb; then
    out=$(adb_run "$1"); rc=$?
    if [ "$rc" -eq 0 ] && { [ -n "$2" ] || ! elev_bad "$out"; }; then ELEV_OUT="$out"; return 0; fi
    errs="$errs | adb: $out"
  fi
  [ -z "$errs" ] && errs="ไม่มีสิทธิ์ยกระดับ (เปิดรูทที่ตั้งค่า ข้อ 4 หรือตั้ง ADB ที่เมนู a ข้อ 11)"
  ELEV_OUT="${errs# | }"
  return 1
}
root_test() {
  local p out rc t0 ok=0
  banner
  printf '\n%sทดสอบสิทธิ์ root (su)%s\n' "$C" "$N"
  p=$(find_su)
  if [ -z "$p" ]; then
    printf ' %s✗ ไม่พบไฟล์ su ในเครื่อง%s\n' "$R" "$N"
    printf '   → ต้องเปิด Root ของอินสแตนซ์ก่อน (ในตั้งค่าของ Redfinger) แล้วรีสตาร์ทเครื่อง\n'
  else
    printf ' พบ su ที่: %s\n' "$p"
    printf ' กำลังขอสิทธิ์ (ถ้ามีหน้าต่างเด้ง ให้กดอนุญาตภายใน %s วิ)...\n' "${SU_TIMEOUT:-20}"
    t0=$SECONDS
    out=$(ROOTSH_ON=0 su_run 'id'); rc=$?
    if [ "$rc" -eq 0 ] && grep -q 'uid=0' <<<"$out"; then
      ok=1
      printf ' %s✓ ใช้ root ได้%s : %s (ใช้เวลา %s วิ)\n' "$G" "$N" "$(trunc "$out" 60)" "$((SECONDS - t0))"
    elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
      printf ' %s✗ หมดเวลา%s น่าจะมีหน้าต่างขอสิทธิ์ค้างอยู่ กดอนุญาตให้ Termux แล้วลองใหม่\n' "$R" "$N"
    else
      printf ' %s✗ ใช้ su ไม่ได้%s : %s\n' "$R" "$N" "$(trunc "$out" 100)"
      printf '   → Termux ยังไม่ได้รับสิทธิ์ root (ดูในแอปจัดการรูทของเครื่อง)\n'
    fi
  fi
  if [ "$ok" -eq 1 ]; then
    if [ "$(cfg_get USE_ROOT 0)" != "1" ]; then
      printf '\n %sสคริปต์ยังปิด "ใช้รูท" อยู่ (ตั้งค่า ข้อ 4) จึงยังไม่ใช้ su%s\n' "$Y" "$N"
      if confirm " เปิดใช้รูทในสคริปต์เลยไหม?"; then cfg_set USE_ROOT 1; fi
    fi
    if [ "$(cfg_get USE_ROOT 0)" = "1" ] && [ "$ROOTSH_ON" != "1" ]; then
      printf ' ⏳ เปิด root shell ค้างไว้ (ครั้งเดียว คำสั่งต่อไปจะเร็วขึ้น)...\n'
      t0=$SECONDS
      if rootsh_start; then printf ' %s✓ พร้อมใช้งาน%s (ใช้เวลา %s วิ)\n' "$G" "$N" "$((SECONDS - t0))"
      else printf ' %s✗ เปิด root shell ค้างไม่ได้ จะใช้ su ทีละคำสั่งแทน%s\n' "$Y" "$N"; fi
    fi
  fi
  printf '\n ใช้รูทในสคริปต์: %s (ตั้งค่า ข้อ 4) | root shell ค้างไว้: %s\n' "$(onoff "$(cfg_get USE_ROOT 0)")" "$(onoff "$ROOTSH_ON")"
  if have_adb; then
    out=$(adb_run 'id'); printf ' ADB (%s): %s\n' "$(cfg_get ADB_SERIAL)" "$(trunc "$out" 80)"
  else
    printf ' ADB: ยังไม่ได้ตั้ง (เมนู a ข้อ 11)\n'
  fi
  pause
}
adb_setup() {
  local s out
  banner
  printf '\n%sตั้งค่า ADB (ทางเลือกแทนรูท)%s\n' "$C" "$N"
  printf '%sต้องเปิด ADB/Wireless debugging ของเครื่องก่อน (Redfinger: ดูตัวเลือก ADB ในตั้งค่า)%s\n\n' "$DIM" "$N"
  if ! command -v adb >/dev/null 2>&1; then
    printf ' ยังไม่มี adb ใน Termux\n'
    if confirm " ติดตั้ง android-tools ตอนนี้?"; then pkg install -y android-tools; fi
    if ! command -v adb >/dev/null 2>&1; then pause; return; fi
  fi
  ask "ที่อยู่ ADB เช่น 127.0.0.1:5555 (- = ลบ)" "$(cfg_get ADB_SERIAL 127.0.0.1:5555)"
  s="$REPLY_VAL"
  if [ -z "$s" ]; then rm -f "$CFG/ADB_SERIAL"; echo "ลบแล้ว"; sleep 1; return; fi
  out=$(timeout 15 adb connect "$s" 2>&1 </dev/null); printf ' %s\n' "$out"
  out=$(timeout 15 adb -s "$s" shell id 2>&1 </dev/null)
  if grep -qE 'uid=(2000|0)' <<<"$out"; then
    cfg_set ADB_SERIAL "$s"
    printf ' %s✓ เชื่อมต่อได้%s : %s\n' "$G" "$N" "$(trunc "$out" 60)"
    log INFO "ตั้ง ADB $s"
  else
    printf ' %s✗ ใช้ไม่ได้%s : %s\n' "$R" "$N" "$(trunc "$out" 100)"
    printf '   ถ้าขึ้น unauthorized ให้กดอนุญาตการดีบักบนเครื่อง แล้วลองใหม่\n'
  fi
  pause
}
priv() {
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && ! elev_bad "$out"; then PRIV_OUT="$out"; return 0; fi
  if elev_run "$(printf '%q ' "$@")"; then PRIV_OUT="$ELEV_OUT"; return 0; fi
  PRIV_OUT="${ELEV_OUT:-$out}"
  return 1
}
sdk_level() { local s; s=$(getprop ro.build.version.sdk 2>/dev/null); printf '%s' "${s:-0}"; }
launch_mode() {
  local m
  m=$(cfg_get LAUNCH_MODE auto)
  if [ "$m" = "auto" ]; then
    if [ "$(sdk_level)" -ge 31 ] 2>/dev/null; then m=window; else m=normal; fi
  fi
  printf '%s' "$m"
}
display_rotated() {
  case "$(cfg_get ROTATE_MODE auto)" in
    swap) return 0 ;;
    off)  return 1 ;;
  esac
  dumpsys window displays 2>/dev/null | grep -qE 'ROTATION_(90|270)'
}
display_size() {
  local d w h
  d=$(cfg_get DISPLAY_SIZE)
  if [ -n "$d" ]; then printf '%s' "$d"; return; fi
  d=$(wm size 2>/dev/null | grep -E 'Override size|Physical size' | tail -n 1 | grep -oE '[0-9]+x[0-9]+')
  d="${d:-1080x1920}"
  if display_rotated; then w=${d%x*}; h=${d#*x}; d="${h}x${w}"; fi
  printf '%s' "$d"
}
slot_info() {
  local p i=0 found=-1
  for p in "${PKGS[@]}"; do
    [ "$(screen_enabled "$p")" = "1" ] || continue
    [ "$p" = "$1" ] && found=$i
    i=$((i + 1))
  done
  [ "$found" -ge 0 ] || return 1
  SLOT_I=$found; SLOT_N=$i
}
grid_rect() {
  local i="$1" n="$2" W="$3" H="$4" cols="${5:-0}" rows cw ch c r
  if [ "$cols" -le 0 ] 2>/dev/null; then
    cols=$(awk -v n="$n" 'BEGIN{c=int(sqrt(n)); if(c*c<n)c++; if(c<1)c=1; print c}')
  fi
  rows=$(( (n + cols - 1) / cols ))
  cw=$((W / cols)); ch=$((H / rows))
  c=$((i % cols)); r=$((i / cols))
  printf '%s %s %s %s' "$((c * cw))" "$((r * ch))" "$((c * cw + cw))" "$((r * ch + ch))"
}
dump_activities() {
  local out
  out=$(dumpsys activity activities 2>&1)
  case "$out" in
    ''|*"Permission Denial"*|*"Can't find service"*)
      if elev_run 'dumpsys activity activities' nocheck; then out="$ELEV_OUT"; else out=""; fi ;;
  esac
  printf '%s' "$out"
}
parse_task_id() {
  local esc t text="$2"
  esc=$(printf '%s' "$1" | sed 's/\./\\./g')
  t=$(grep -E "Task\{[^}]* #[0-9]+ [^}]*A=[0-9]+:${esc}[ }]" <<<"$text" | head -n 1 | sed -n 's/.*Task{[^ ]* #\([0-9]*\) .*/\1/p')
  [ -z "$t" ] && t=$(grep -E "taskId=[0-9]+: ?${esc}/" <<<"$text" | head -n 1 | sed -n 's/.*taskId=\([0-9]*\):.*/\1/p')
  [ -z "$t" ] && t=$(grep -E "Task\{[^}]*#[0-9]+[ }].*${esc}([^A-Za-z0-9_.]|$)" <<<"$text" | head -n 1 | sed -n 's/.*Task{[^ ]* #\([0-9]*\)[ }].*/\1/p')
  [ -z "$t" ] && t=$(grep -E "ActivityRecord\{[^}]* u[0-9]+ ${esc}/[^ ]* t[0-9]+\}" <<<"$text" | head -n 1 | sed -n 's/.* t\([0-9]*\)}.*/\1/p')
  printf '%s' "$t"
}
find_task_id() { parse_task_id "$1" "$(dump_activities)"; }
dump_for_pkg() {
  local pkg="$1" c out
  DUMP_TEXT=""; DUMP_SRC=""
  for c in 'dumpsys activity activities' 'dumpsys activity recents' 'am stack list'; do
    out=$($c 2>&1)
    if ! grep -qE 'Permission Denial|Can.t find service' <<<"$out" && grep -qF "$pkg" <<<"$out"; then
      DUMP_TEXT="$out"; DUMP_SRC="$c (ตรง)"; return 0
    fi
    if elev_run "$c" nocheck && grep -qF "$pkg" <<<"$ELEV_OUT"; then
      DUMP_TEXT="$ELEV_OUT"; DUMP_SRC="$c (สิทธิ์สูง)"; return 0
    fi
  done
  return 1
}
resize_task() { # id l t r b
  priv am task resize "$1" "$2" "$3" "$4" "$5" && return 0
  priv am task resize "$1" "$2,$3,$4,$5" && return 0
  return 1
}
parse_task_mode_by_id() {
  grep -E "Task\{[^}]* #$1 [^}]*mode=[a-z-]+" <<<"$2" | head -n 1 | sed -n 's/.*mode=\([a-z-]*\).*/\1/p'
}
place_window() {
  local pkg="$1" tid mode wh W H rect l t r b tries
  slot_info "$pkg" || return 0
  wh=$(display_size); W=${wh%x*}; H=${wh#*x}
  rect=$(grid_rect "$SLOT_I" "$SLOT_N" "$W" "$H" "$(cfg_get GRID_COLS 0)")
  read -r l t r b <<<"$rect"
  for tries in 1 2 3; do
    sleep "$(cfg_get WIN_SETTLE 3)"
    dump_for_pkg "$pkg"
    tid=$(parse_task_id "$pkg" "$DUMP_TEXT")
    [ -n "$tid" ] && break
  done
  if [ -z "$tid" ]; then
    printf '   %s⚠ หา task ของหน้าต่างไม่เจอ (จัดตำแหน่งไม่ได้)%s\n' "$Y" "$N"
    printf '   %s  ดูสาเหตุ: เมนู a ข้อ 12 (ดีบัก)%s\n' "$DIM" "$N"
    log WARN "$pkg หา task id ไม่เจอ จัดหน้าต่างไม่ได้"
    return 1
  fi
  mode=$(parse_task_mode_by_id "$tid" "$DUMP_TEXT")
  if [ -n "$mode" ] && [ "$mode" != "freeform" ]; then
    printf '   %s⚠ ระบบเปิดเป็นโหมด "%s" ไม่ใช่หน้าต่างอิสระ%s\n' "$Y" "$mode" "$N"
    printf '   %s  ลองเมนู a ข้อ 2 แล้วรีสตาร์ท หรือดูข้อ 8 (ทดสอบ)%s\n' "$DIM" "$N"
    log WARN "$pkg task=$tid โหมด=$mode (ไม่ใช่ freeform)"
    return 1
  fi
  if resize_task "$tid" "$l" "$t" "$r" "$b"; then
    printf '   🪟 จัดหน้าต่างช่อง %s/%s (%s,%s → %s,%s)\n' "$((SLOT_I + 1))" "$SLOT_N" "$l" "$t" "$r" "$b"
    log INFO "$pkg จัดหน้าต่าง task=$tid ช่อง $((SLOT_I + 1))/$SLOT_N [$l,$t,$r,$b]"
  else
    printf '   %s⚠ ปรับขนาดหน้าต่างไม่สำเร็จ: %s%s\n' "$Y" "$(trunc "$PRIV_OUT" 100)" "$N"
    log WARN "$pkg resize task=$tid ไม่สำเร็จ: $(trunc "$PRIV_OUT" 120)"
    return 1
  fi
}
win_debug() {
  local pkg c out n lines
  banner; load_pkgs || return
  for pkg in "${PKGS[@]}"; do [ "$(screen_enabled "$pkg")" = "1" ] && break; done
  printf '\n%sดีบัก task ของ %s%s\n' "$C" "$pkg" "$N"
  printf ' ต้องเปิดแอปนี้ค้างไว้ก่อน (เปิดแบบ window จากเมนูหลัก)\n'
  for c in 'dumpsys activity activities' 'dumpsys activity recents' 'am stack list'; do
    printf '\n%s▶ %s%s\n' "$Y" "$c" "$N"
    out=$($c 2>&1)
    if grep -qE 'Permission Denial|Can.t find service' <<<"$out" || [ -z "$out" ]; then
      printf '  (สั่งตรงไม่ได้ → ลองสิทธิ์สูง)\n'
      if elev_run "$c" nocheck; then out="$ELEV_OUT"; else out=""; printf '  สิทธิ์สูงก็ไม่ได้: %s\n' "$(trunc "$ELEV_OUT" 100)"; fi
    fi
    n=$(printf '%s\n' "$out" | grep -c .)
    lines=$(grep -F "$pkg" <<<"$out" | head -n 6)
    printf '  ได้ข้อมูล %s บรรทัด | บรรทัดที่มีชื่อแอป: %s\n' "$n" "$(printf '%s\n' "$lines" | grep -c .)"
    [ -n "$lines" ] && while IFS= read -r l; do printf '   %s\n' "$(trunc "$l" 150)"; done <<<"$lines"
    printf '  task id ที่อ่านได้: %s\n' "$(parse_task_id "$pkg" "$out")"
  done
  printf '\n%sส่งข้อความตรงนี้มาให้ผมดูได้ครับ%s\n' "$DIM" "$N"
  pause
}
win_out_bad() { grep -qiE 'permission denial|securityexception|exception|error:|usage:|not allowed|unknown option' <<<"$1"; }
launch_window() {
  local pkg="$1" uri="$2" order v rc out
  local -a argv
  WIN_ERR=""
  if [ "$(cfg_get WIN_VARIANT 1)" = "2" ]; then order="2 1"; else order="1 2"; fi
  for v in $order; do
    argv=(am start --windowingMode 5)
    [ "$v" = "2" ] && argv+=(--user 0)
    if [ -n "$uri" ]; then
      argv+=(-a android.intent.action.VIEW -d "$uri" -p "$pkg")
    else
      argv+=(-a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p "$pkg")
    fi
    if [ "$v" = "2" ]; then
      if elev_run "$(printf '%q ' "${argv[@]}")"; then rc=0; else rc=1; fi
      out="$ELEV_OUT"
    else
      out=$("${argv[@]}" 2>&1); rc=$?
    fi
    if [ "$rc" -eq 0 ] && ! win_out_bad "$out"; then
      cfg_set WIN_VARIANT "$v"
      return 0
    fi
    WIN_ERR="$WIN_ERR | วิธี $v: $(trunc "$out" 140)"
  done
  WIN_ERR="${WIN_ERR# | }"
  log WARN "$pkg เปิดแบบหน้าต่างไม่สำเร็จ: $WIN_ERR"
  return 99
}
win_test() {
  local pkg rc
  banner; load_pkgs || return
  for pkg in "${PKGS[@]}"; do [ "$(screen_enabled "$pkg")" = "1" ] && break; done
  printf '\n%sทดสอบเปิด %s แบบหน้าต่าง...%s\n' "$C" "$pkg" "$N"
  launch_window "$pkg" ""; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s✓ สั่งเปิดแบบหน้าต่างสำเร็จ (วิธี %s)%s\n' "$G" "$(cfg_get WIN_VARIANT 1)" "$N"
    place_window "$pkg"
  else
    printf '%s✗ ไม่สำเร็จ%s\n%s\n' "$R" "$N" "$WIN_ERR"
    case "$WIN_ERR" in
      *ermission*|*ecurity*) printf '\n%sต้องใช้สิทธิ์สูง: เปิดตั้งค่า ข้อ 4 + อนุญาตให้ Termux ใช้ su (ดูเมนู a ข้อ 10) หรือตั้ง ADB (ข้อ 11)%s\n' "$Y" "$N" ;;
    esac
  fi
  pause
}
launch_smart() {
  local pkg="$1" uri="$2" rc
  if [ "$(launch_mode)" = "window" ]; then
    launch_window "$pkg" "$uri"; rc=$?
    if [ "$rc" -eq 0 ]; then place_window "$pkg"; return 0; fi
    printf '   %s⚠ เปิดแบบหน้าต่างไม่ได้ → ใช้โหมดปกติ%s\n   %s%s%s\n' "$Y" "$N" "$DIM" "${WIN_ERR:0:220}" "$N"
  fi
  if [ -n "$uri" ]; then launch_deeplink "$pkg" "$uri"; else launch_app "$pkg"; fi
}
a12_enable_freeform() {
  local kv k v ok=0
  printf '\n%sเปิดฟีเจอร์หน้าต่างอิสระ%s\n' "$C" "$N"
  for kv in "enable_freeform_support 1" "force_resizable_activities 1" "freeform_window_management 1"; do
    k=${kv% *}; v=${kv#* }
    if priv settings put global "$k" "$v"; then
      printf '  %s✓%s %s=%s\n' "$G" "$N" "$k" "$v"; ok=$((ok + 1))
    else
      printf '  %s✗%s %s (%s)\n' "$R" "$N" "$k" "$(trunc "$PRIV_OUT" 60)"
    fi
  done
  if [ "$ok" -eq 0 ]; then
    printf '\n%sไม่มีสิทธิ์เขียนค่าระบบ: เปิด "ใช้รูท" ในตั้งค่า (ถ้ามีรูท) หรือเปิด Freeform จากตัวเลือกนักพัฒนา%s\n' "$Y" "$N"
  else
    printf '\n%sถ้าหน้าต่างยังไม่แยก ให้รีสตาร์ทเครื่อง/อินสแตนซ์หนึ่งครั้งแล้วลองใหม่%s\n' "$DIM" "$N"
  fi
  log INFO "เปิด freeform สำเร็จ $ok/3 รายการ"
}
a12_tune() {
  local p g ok=0 fail=0
  local -a G_CMDS=(
    "device_config set_sync_disabled_for_tests persistent"
    "device_config put activity_manager max_phantom_processes 2147483647"
    "settings put global settings_enable_monitor_phantom_procs false"
    "settings put global cached_apps_freezer disabled"
  )
  printf '\n%sปรับระบบกันแอปโดนปิดเบื้องหลัง%s\n' "$C" "$N"
  for g in "${G_CMDS[@]}"; do
    if priv $g; then printf '  %s✓%s %s\n' "$G" "$N" "$g"; ok=$((ok + 1))
    else printf '  %s✗%s %s\n' "$R" "$N" "$g"; fail=$((fail + 1)); fi
  done
  for p in "${PKGS[@]}"; do
    [ "$(screen_enabled "$p")" = "1" ] || continue
    printf '  %s%s%s\n' "$Y" "$p" "$N"
    for g in "cmd deviceidle whitelist +$p" "cmd appops set $p RUN_IN_BACKGROUND allow" \
             "cmd appops set $p RUN_ANY_IN_BACKGROUND allow" "am set-standby-bucket $p active"; do
      if priv $g; then ok=$((ok + 1)); else fail=$((fail + 1)); printf '    %s✗%s %s\n' "$R" "$N" "$g"; fi
    done
  done
  printf '\n%sสำเร็จ %s | ไม่สำเร็จ %s%s\n' "$Y" "$ok" "$fail" "$N"
  [ "$fail" -gt 0 ] && printf '%sคำสั่งที่ไม่สำเร็จมักเป็นเพราะไม่มีสิทธิ์ shell/root%s\n' "$DIM" "$N"
  log INFO "a12_tune ok=$ok fail=$fail"
}
relayout_all() {
  local p
  for p in "${PKGS[@]}"; do
    [ "$(screen_enabled "$p")" = "1" ] || continue
    printf '\n%s%s%s\n' "$C" "$p" "$N"
    place_window "$p"
  done
}
a12_diag() {
  local fr tid p n
  banner; load_pkgs || return
  printf '\n%sข้อมูลระบบ%s\n' "$C" "$N"
  printf ' Android %s (SDK %s) | โหมดที่จะใช้: %s\n' "$(getprop ro.build.version.release 2>/dev/null)" "$(sdk_level)" "$(launch_mode)"
  printf ' uid ผู้ใช้: %s | su: %s | ใช้รูท: %s\n' "$(id -u 2>/dev/null)" \
    "$(have_su && echo มี || echo ไม่มี)" "$(onoff "$(cfg_get USE_ROOT 0)")"
  fr=$(settings get global enable_freeform_support 2>/dev/null)
  printf ' enable_freeform_support = %s\n' "${fr:-อ่านไม่ได้}"
  printf ' ขนาดจอ: %s | ตาราง: %s คอลัมน์ (0=อัตโนมัติ)\n' "$(display_size)" "$(cfg_get GRID_COLS 0)"
  printf ' คำสั่ง am task: %s\n' "$(am help 2>&1 | grep -q 'task resize' && echo มี || echo ไม่พบ)"
  printf ' dumpsys activity: %s\n' "$([ -n "$(dump_activities | head -n 1)" ] && echo อ่านได้ || echo อ่านไม่ได้)"
  n=0
  printf '\n%sหน้าต่างที่เปิดอยู่ตอนนี้%s\n' "$C" "$N"
  for p in "${PKGS[@]}"; do
    tid=$(find_task_id "$p")
    printf ' %s : task=%s\n' "$p" "${tid:--}"
  done
  printf '\n%sวิธีทดสอบ: เปิดเกมผ่านเมนู 1 ด้วยโหมด window แล้วดูว่าแต่ละจอแยกหน้าต่างหรือไม่%s\n' "$DIM" "$N"
  pause
}
menu_android12() {
  local c v
  while true; do
    banner
    printf '%sAndroid 12 / โหมดหน้าต่างอิสระ (แยกจอ)%s\n\n' "$Y" "$N"
    printf ' Android %s (SDK %s)\n\n' "$(getprop ro.build.version.release 2>/dev/null)" "$(sdk_level)"
    printf ' 1) โหมดเปิดแอป : %s (auto/normal/window) → ตอนนี้ใช้: %s\n' "$(cfg_get LAUNCH_MODE auto)" "$(launch_mode)"
    printf ' 2) เปิดฟีเจอร์หน้าต่างอิสระของระบบ (ต้องมีสิทธิ์)\n'
    printf ' 3) ปรับระบบกันแอปโดนปิดเบื้องหลัง (ต้องมีสิทธิ์)\n'
    printf ' 4) จัดตำแหน่งหน้าต่างใหม่ทุกจอ (ไม่ต้องเปิดเกมใหม่)\n'
    printf ' 5) ตาราง : %s คอลัมน์ (0=อัตโนมัติ)\n' "$(cfg_get GRID_COLS 0)"
    printf ' 6) ขนาดจอ : %s (เว้นว่าง=อัตโนมัติ)\n' "$(display_size)"
    printf ' 7) ทดสอบสิทธิ์ / วินิจฉัย\n'
    printf ' 8) ทดสอบเปิดแบบหน้าต่าง (แสดงข้อผิดพลาดจริง)\n'
    printf ' 9) หมุนจอ/สลับกว้าง-สูง : %s (auto/swap/off)\n' "$(cfg_get ROTATE_MODE auto)"
    printf '10) ทดสอบสิทธิ์ root (su)\n'
    printf '12) ดีบัก: ดูข้อมูล task ของแอป (ใช้เมื่อจัดหน้าต่างไม่ได้)\n'
    printf '11) ตั้งค่า ADB (ทางเลือกแทนรูท) : %s\n' "$(cfg_get ADB_SERIAL ยังไม่ตั้ง)"
    printf ' 0) กลับ\n\n'
    read -rp "เลือก: " c || on_exit
    case "$c" in
      1) ask "โหมด (auto/normal/window)" "$(cfg_get LAUNCH_MODE auto)"
         case "$REPLY_VAL" in auto|normal|window) cfg_set LAUNCH_MODE "$REPLY_VAL" ;; esac ;;
      2) a12_enable_freeform; pause ;;
      3) banner; load_pkgs && { a12_tune; pause; } ;;
      4) banner; load_pkgs && { relayout_all; pause; } ;;
      5) set_num GRID_COLS "กี่คอลัมน์ (0=อัตโนมัติ)" 0 0 ;;
      6) ask "ขนาดจอ เช่น 1080x1920 (- = อัตโนมัติ)" "$(cfg_get DISPLAY_SIZE)"
         v="$REPLY_VAL"
         if [ -z "$v" ]; then rm -f "$CFG/DISPLAY_SIZE"
         elif [[ "$v" =~ ^[0-9]+x[0-9]+$ ]]; then cfg_set DISPLAY_SIZE "$v"; fi ;;
      7) a12_diag ;;
      8) win_test ;;
      10) root_test ;;
      12) win_debug ;;
      11) adb_setup ;;
      9) ask "หมุนจอ (auto/swap/off)" "$(cfg_get ROTATE_MODE auto)"
         case "$REPLY_VAL" in auto|swap|off) cfg_set ROTATE_MODE "$REPLY_VAL" ;; esac ;;
      0) return ;;
    esac
  done
}
CK_UID=""; CK_NAME=""; CK_ERR=""; CK_HTTP=""; CK_WORK=""
declare -A W_BADCK=()
pkg_cookie() { [ -s "$CFG/cookie.$1" ] && cat "$CFG/cookie.$1"; }
ck_normalize() {
  local in="${1//$'\r'/}" c re='^[A-Za-z0-9._|:%+/=-]{80,}$'
  c=$(printf '%s' "$in" | grep -oE '_\|WARNING:[A-Za-z0-9._|:%+/=-]+' | head -n 1)
  if [ -z "$c" ]; then
    c="${in#*.ROBLOSECURITY=}"
    c=$(printf '%s' "$c" | tr -d '[:space:]"'"'"';')
    [[ "$c" =~ $re ]] || c=""
  fi
  printf '%s' "$c"
}
ck_hdr() {
  local f
  f=$(umask 077; mktemp "$STATE/.ckh.XXXXXX") || return 1
  printf 'Cookie: .ROBLOSECURITY=%s\n' "$1" > "$f"
  printf '%s' "$f"
}
cookie_check() {
  local h body
  CK_UID=""; CK_NAME=""; CK_HTTP=""
  h=$(ck_hdr "$1") || return 2
  body=$(curl -s -m 15 -A "$JOIN_UA" -H @"$h" -w $'\n%{http_code}' https://users.roblox.com/v1/users/authenticated 2>/dev/null)
  rm -f "$h"
  CK_HTTP="${body##*$'\n'}"; body="${body%$'\n'*}"
  [ -n "$CK_HTTP" ] && [ "$CK_HTTP" != "000" ] || return 2
  [ "$CK_HTTP" = "200" ] || return 1
  CK_UID=$(grep -oE '"id":[0-9]+' <<<"$body" | head -n 1 | cut -d: -f2)
  CK_NAME=$(grep -oE '"name":"[^"]*"' <<<"$body" | head -n 1 | cut -d'"' -f4)
  [ -n "$CK_UID" ]
}
cookie_save() { # แพ็กเกจ คุกกี้ (ใช้ค่า CK_UID/CK_NAME ล่าสุด)
  ( umask 077; printf '%s' "$2" > "$CFG/cookie.$1" )
  chmod 600 "$CFG/cookie.$1" 2>/dev/null
  [ -n "$CK_UID" ] && cfg_set "uid.$1" "$CK_UID"
  [ -n "$CK_NAME" ] && cfg_set "uname.$1" "$CK_NAME"
}
cookie_delete() { rm -f "$CFG/cookie.$1" "$CFG/uid.$1" "$CFG/uname.$1"; }
ck_wipe() {
  local d="$1"
  [ -n "$d" ] && [ -e "$d" ] || return 0
  chmod u+rwx "$d" 2>/dev/null
  chmod -R u+rwX "$d" 2>/dev/null
  rm -rf "$d" 2>/dev/null
  [ -e "$d" ] || return 0
  if [ "$(cfg_get USE_ROOT 0)" = "1" ] && have_su; then
    su_run "chmod -R u+rwX '$d' 2>/dev/null; rm -rf '$d'" >/dev/null 2>&1
  fi
  if [ -e "$d" ]; then
    log WARN "ลบโฟลเดอร์ชั่วคราวไม่สำเร็จ: $d"
    return 1
  fi
  return 0
}
ck_inject_core() {
  local pkg="$1" ck="$2" db work="$CK_WORK" tuid auid out cols n t nn
  local names="" vals="" v now exp sql re='^[A-Za-z0-9._|:%+/=-]+$'
  CK_ERR=""
  command -v sqlite3 >/dev/null 2>&1 || { CK_ERR="ไม่มี sqlite3 (พิมพ์: pkg install sqlite)"; return 1; }
  if [ "$(cfg_get USE_ROOT 0)" != "1" ] || ! have_su; then CK_ERR="ต้องเปิดใช้รูท (ตั้งค่า ข้อ 4)"; return 1; fi
  [[ "$ck" =~ $re ]] || { CK_ERR="รูปแบบคุกกี้ไม่ถูกต้อง"; return 1; }
  db="/data/data/$pkg/app_webview/Default/Cookies"
  tuid=$(id -u)
  auid=$(su_run "stat -c %u /data/data/$pkg" 2>/dev/null); auid="${auid//[^0-9]/}"
  [ -n "$auid" ] || { CK_ERR="ไม่พบข้อมูลแอป $pkg"; return 1; }
  su_run "[ -f '$db' ]" >/dev/null 2>&1 || {
    CK_ERR="ยังไม่มีไฟล์คุกกี้ของแอป (เปิดแอปค้างไว้สักครู่หนึ่งครั้งก่อนแล้วปิด)"; return 1
  }
  out=$(su_run "
    for f in '$db' '$db-journal' '$db-wal' '$db-shm'; do
      [ -f \"\$f\" ] && cp \"\$f\" '$work/'
    done
    chown -R $tuid:$tuid '$work'
    chmod 700 '$work'
    chmod 600 '$work'/* 2>/dev/null
    ls -l '$work'
    echo COPIED")
  if [ ! -s "$work/Cookies" ]; then
    CK_ERR="คัดลอกไฟล์คุกกี้ไม่สำเร็จ: $(trunc "$out" 120)"
    log WARN "$pkg copy cookie ล้มเหลว: $(trunc "$out" 200)"
    return 1
  fi
  cols=$(sqlite3 "$work/Cookies" "SELECT name||'|'||type||'|'||\"notnull\" FROM pragma_table_info('cookies');" 2>&1)
  grep -q '^name|' <<<"$cols" || { CK_ERR="อ่านโครงสร้างไฟล์คุกกี้ไม่ได้: $(trunc "$cols" 80)"; return 1; }
  now="((strftime('%s','now')+11644473600)*1000000)"
  exp="((strftime('%s','now')+11644473600+31536000)*1000000)"
  while IFS='|' read -r n t nn; do
    [ -n "$n" ] || continue
    case "$n" in
      creation_utc|last_access_utc|last_update_utc) v="$now" ;;
      host_key) v="'.roblox.com'" ;;
      name) v="'.ROBLOSECURITY'" ;;
      value) v="'$ck'" ;;
      encrypted_value) v="x''" ;;
      path) v="'/'" ;;
      expires_utc) v="$exp" ;;
      is_secure|is_httponly|has_expires|is_persistent|priority) v=1 ;;
      samesite) v=-1 ;;
      source_scheme) v=2 ;;
      source_port) v=443 ;;
      top_frame_site_key) v="''" ;;
      *) case "${t^^}" in INT*|BIGINT*|BOOL*|NUM*) v=0 ;; BLOB) v="x''" ;; *) v="''" ;; esac ;;
    esac
    names+="${names:+,}\"$n\""; vals+="${vals:+,}$v"
  done <<<"$cols"
  sql="DELETE FROM cookies WHERE name='.ROBLOSECURITY' AND host_key LIKE '%roblox.com';
INSERT INTO cookies ($names) VALUES ($vals);
PRAGMA wal_checkpoint(TRUNCATE);
PRAGMA journal_mode=DELETE;
SELECT length(value) FROM cookies WHERE name='.ROBLOSECURITY' AND host_key='.roblox.com';"
  out=$(printf '%s\n' "$sql" | sqlite3 "$work/Cookies" 2>&1)
  grep -qx "${#ck}" <<<"$out" || { CK_ERR="เขียนคุกกี้ลงไฟล์ไม่สำเร็จ: $(trunc "$out" 100)"; return 1; }
  out=$(su_run "
    if cp '$work/Cookies' '$db' \
       && rm -f '$db-journal' '$db-wal' '$db-shm' \
       && chown $auid:$auid '$db' && chmod 660 '$db'; then
      restorecon '$db' >/dev/null 2>&1
      echo COPY_OK
    else
      echo COPY_FAIL
    fi")
  grep -q 'COPY_OK' <<<"$out" || { CK_ERR="เขียนไฟล์กลับเข้าแอปไม่สำเร็จ: $(trunc "$out" 80)"; return 1; }
  return 0
}
cookie_inject() {
  local rc
  CK_ERR=""
  ck_wipe "$STATE/ckwork"                    # เคลียร์ซากจากรอบก่อนที่ค้างอยู่
  CK_WORK=$(umask 077; mktemp -d "$STATE/ckwork.XXXXXX") || { CK_ERR="สร้างโฟลเดอร์ชั่วคราวไม่ได้"; return 1; }
  chmod 700 "$CK_WORK"
  ck_inject_core "$1" "$2"; rc=$?
  ck_wipe "$CK_WORK" || true
  CK_WORK=""
  return "$rc"
}
alive_cookie() {
  local pkg="$1" ck uid want
  ck=$(pkg_cookie "$pkg"); [ -n "$ck" ] || return 2
  uid=$(cfg_get "uid.$pkg")
  if [ -z "$uid" ]; then
    cookie_check "$ck" && { uid="$CK_UID"; cfg_set "uid.$pkg" "$uid"; }
  fi
  [ -n "$uid" ] || return 2
  if ! get_presence "$uid" "$ck"; then
    if [ "$PRES_HTTP" = "401" ]; then
      if [ "${W_BADCK[$pkg]:-0}" != "1" ]; then
        W_BADCK[$pkg]=1
        log ERROR "$pkg คุกกี้ใช้ไม่ได้/หมดอายุ (401)"
        notify_rejoin "🔑 $pkg" "คุกกี้ใช้ไม่ได้หรือหมดอายุ ต้องใส่ใหม่" 15158332
      fi
    fi
    return 2
  fi
  W_BADCK[$pkg]=0
  sleep 1
  case "$PRES_TYPE" in
    2) ;;
    0|1|3) return 1 ;;
    *) return 2 ;;
  esac
  if [ "$(cfg_get RJ_STRICT 1)" = "1" ]; then
    want=$(saved_uri "$pkg" | sed -n 's/.*placeId=\([0-9]*\).*/\1/p')
    if [ -n "$want" ] && [ "$PRES_PLACE" != "$want" ] && [ "$PRES_ROOT" != "$want" ]; then
      return 1
    fi
  fi
  return 0
}
cookie_list() {
  local i p
  printf '\n%sจอ / แพ็กเกจ / บัญชี%s\n' "$C" "$N"
  for i in "${!PKGS[@]}"; do
    p="${PKGS[$i]}"
    if [ -s "$CFG/cookie.$p" ]; then
      printf '  %s) %s  %s🔑 %s (%s)%s\n' "$((i + 1))" "$p" "$G" "$(cfg_get "uname.$p" "?")" "$(cfg_get "uid.$p" "-")" "$N"
    else
      printf '  %s) %s  %s— ยังไม่มีคุกกี้%s\n' "$((i + 1))" "$p" "$DIM" "$N"
    fi
  done
}
cookie_set_screens() {
  local idx pkg v c
  for idx in "${SELECTED[@]}"; do
    pkg="${PKGS[$idx]}"
    printf '\n%sจอ %s: %s%s\n' "$C" "$((idx + 1))" "$pkg" "$N"
    printf 'วาง .ROBLOSECURITY (ไม่แสดงบนจอ | Enter=ข้าม | -=ลบ): '
    read -rs v; echo
    v="${v//$'\r'/}"
    case "$v" in
      '') continue ;;
      -)  cookie_delete "$pkg"; echo "ลบแล้ว"; continue ;;
    esac
    c=$(ck_normalize "$v")
    if [ -z "$c" ]; then printf '  %s✗ รูปแบบคุกกี้ไม่ถูกต้อง (ต้องขึ้นต้น _|WARNING:...)%s\n' "$R" "$N"; continue; fi
    if cookie_check "$c"; then
      cookie_save "$pkg" "$c"
      printf '  %s✓ บัญชี %s (%s)%s\n' "$G" "$CK_NAME" "$CK_UID" "$N"
      log INFO "ตั้งคุกกี้ $pkg -> uid=$CK_UID"
    elif [ "$CK_HTTP" = "401" ]; then
      printf '  %s✗ คุกกี้ใช้ไม่ได้ / หมดอายุ%s\n' "$R" "$N"
    else
      printf '  %s✗ ตรวจกับ Roblox ไม่ได้ (HTTP %s) ตรวจอินเทอร์เน็ตแล้วลองใหม่%s\n' "$R" "${CK_HTTP:-ไม่มี}" "$N"
    fi
  done
}
cookie_import_file() {
  local f p i=0 total
  local -a lines=() epk=()
  ask "ไฟล์คุกกี้ (บรรทัดละ 1 บัญชี)" "$(cfg_get COOKIE_FILE /sdcard/cookies.txt)"
  f="$REPLY_VAL"
  if [ ! -r "$f" ]; then printf '%s✗ อ่านไฟล์ไม่ได้: %s%s\n' "$R" "$f" "$N"; return; fi
  cfg_set COOKIE_FILE "$f"
  mapfile -t lines < <(grep -oE '_\|WARNING:[A-Za-z0-9._|:%+/=-]+' "$f")
  for p in "${PKGS[@]}"; do [ "$(screen_enabled "$p")" = "1" ] && epk+=("$p"); done
  total=${#lines[@]}
  printf '\nพบคุกกี้ %s อัน | จอที่เปิดใช้งาน %s จอ\n' "$total" "${#epk[@]}"
  [ "$total" -gt "${#epk[@]}" ] && printf '%s⚠ คุกกี้เกินจำนวนจอ ส่วนที่เกินจะถูกข้าม%s\n' "$Y" "$N"
  for p in "${epk[@]}"; do
    [ "$i" -ge "$total" ] && break
    printf ' %s ← ' "$p"
    if cookie_check "${lines[$i]}"; then
      cookie_save "$p" "${lines[$i]}"
      printf '%s✓ %s (%s)%s\n' "$G" "$CK_NAME" "$CK_UID" "$N"
    else
      printf '%s✗ ใช้ไม่ได้ (HTTP %s)%s\n' "$R" "${CK_HTTP:-?}" "$N"
    fi
    i=$((i + 1)); sleep 1
  done
  log INFO "นำเข้าคุกกี้จากไฟล์: $total อัน"
  printf '\n%sแนะนำ: ลบไฟล์คุกกี้ต้นฉบับออกจากเครื่องหลังนำเข้าแล้ว%s\n' "$DIM" "$N"
}
cookie_check_all() {
  local p ck
  for p in "${PKGS[@]}"; do
    ck=$(pkg_cookie "$p"); [ -n "$ck" ] || continue
    printf ' %s : ' "$p"
    if cookie_check "$ck"; then
      printf '%s✓ %s (%s)%s\n' "$G" "$CK_NAME" "$CK_UID" "$N"
      cfg_set "uid.$p" "$CK_UID"; cfg_set "uname.$p" "$CK_NAME"; W_BADCK[$p]=0
    elif [ "$CK_HTTP" = "401" ]; then
      printf '%s✗ หมดอายุ/ใช้ไม่ได้ → ใส่ใหม่ (ข้อ 1)%s\n' "$R" "$N"
    else
      printf '%s? ตรวจไม่ได้ (HTTP %s)%s\n' "$Y" "${CK_HTTP:-?}" "$N"
    fi
    sleep 1
  done
}
cookie_login_screens() {
  local idx pkg ck
  for idx in "${SELECTED[@]}"; do
    pkg="${PKGS[$idx]}"
    ck=$(pkg_cookie "$pkg")
    printf '\n%sจอ %s: %s%s\n' "$C" "$((idx + 1))" "$pkg" "$N"
    if [ -z "$ck" ]; then printf '  %s— ยังไม่มีคุกกี้ (ข้อ 1/2)%s\n' "$Y" "$N"; continue; fi
    force_stop "$pkg"; sleep 1
    if cookie_inject "$pkg" "$ck"; then
      printf '  %s✓ ใส่คุกกี้ลงแอปแล้ว%s (เปิดแอปเพื่อใช้งาน)\n' "$G" "$N"
      log INFO "ล็อกอินด้วยคุกกี้: $pkg"
    else
      printf '  %s✗ %s%s\n' "$R" "$CK_ERR" "$N"
      log WARN "ล็อกอินด้วยคุกกี้ไม่สำเร็จ $pkg: $CK_ERR"
    fi
  done
}
cookie_test() {
  local pkg="" p place uri ck uid i
  banner; load_pkgs || return
  for p in "${PKGS[@]}"; do
    if [ "$(screen_enabled "$p")" = "1" ] && [ -s "$CFG/cookie.$p" ]; then pkg="$p"; break; fi
  done
  if [ -z "$pkg" ]; then printf '%s✗ ไม่มีจอที่เปิดใช้งานและมีคุกกี้%s\n' "$R" "$N"; pause; return; fi
  ck=$(pkg_cookie "$pkg"); uid=$(cfg_get "uid.$pkg")
  printf '\n%sทดสอบล็อกอินด้วยคุกกี้ที่จอ %s%s\n' "$C" "$pkg" "$N"
  ask "Game ID ที่จะเข้า" "$(cfg_get PLACE_ID)"; place=$(norm_place "$REPLY_VAL")
  if [ -z "$place" ]; then printf '%s✗ Game ID ไม่ถูกต้อง%s\n' "$R" "$N"; pause; return; fi
  uri="roblox://placeId=$place"
  force_stop "$pkg"; sleep 1
  printf ' 🔑 ใส่คุกกี้...\n'
  if ! cookie_inject "$pkg" "$ck"; then printf ' %s✗ %s%s\n' "$R" "$CK_ERR" "$N"; pause; return; fi
  printf ' 🚀 เปิดเกม...\n'
  launch_smart "$pkg" "$uri"
  printf ' ⏳ รอ 60 วินาที ให้เข้าเกม'
  for i in 1 2 3 4 5 6; do sleep 10; printf '.'; done; echo
  if [ -z "$uid" ]; then cookie_check "$ck" && uid="$CK_UID"; fi
  if get_presence "$uid" "$ck"; then
    if [ "$PRES_TYPE" = "2" ]; then
      printf ' %s✓ บัญชีอยู่ในเกมแล้ว%s (place %s) → ล็อกอินด้วยคุกกี้ใช้ได้\n' "$G" "$N" "${PRES_PLACE:--}"
    else
      printf ' %s✗ บัญชียังไม่อยู่ในเกม (สถานะ %s)%s\n' "$Y" "$PRES_TYPE" "$N"
      printf ' %s  เป็นไปได้: ยังโหลดไม่เสร็จ (ลองรออีกหน่อยแล้วดูในแอป) หรือแอปเวอร์ชันนี้ไม่ใช้คุกกี้จากไฟล์นี้%s\n' "$DIM" "$N"
    fi
  else
    printf ' %s? เช็คสถานะไม่ได้ (HTTP %s)%s\n' "$Y" "${PRES_HTTP:-?}" "$N"
  fi
  pause
}
menu_cookie() {
  local c sel idx miss p
  while true; do
    banner
    load_pkgs || return
    printf '%s🔑 คุกกี้ / ล็อกอินอัตโนมัติ%s %s(ใช้กับบัญชีของตัวเองเท่านั้น)%s\n' "$Y" "$N" "$DIM" "$N"
    cookie_list
    printf '\n 1) ตั้ง/เปลี่ยนคุกกี้รายจอ (วางทีละจอ แล้วตรวจกับ Roblox)\n'
    printf ' 2) นำเข้าคุกกี้จากไฟล์ (บรรทัดละบัญชี)\n'
    printf ' 3) ตรวจคุกกี้ทุกจอว่ายังใช้ได้ไหม\n'
    printf ' 4) ล็อกอินด้วยคุกกี้ตอนนี้ (ใส่คุกกี้เข้าแอปที่เลือก)\n'
    printf ' 5) เข้าเกมด้วยคุกกี้ (ล็อกอิน + เข้า Game ID/VIP ทุกจอ)\n'
    printf ' 6) ทดสอบล็อกอินด้วยคุกกี้แบบครบวงจร (จอเดียว)\n'
    printf ' 7) ล็อกอินด้วยคุกกี้ก่อนเปิดแอปทุกครั้ง : %s\n' "$(onoff "$(cfg_get COOKIE_AUTOLOGIN 1)")"
    printf ' 8) ตรวจรีจอยจากคุกกี้ : %s (เปิด = ใช้วิธีตรวจ cookie)\n' "$([ "$(cfg_get ALIVE_METHOD auto)" = cookie ] && echo เปิด || echo ปิด)"
    printf ' 9) ตรวจเฉพาะเกมเป้าหมาย (อยู่คนละเกม = รีจอย) : %s\n' "$(onoff "$(cfg_get RJ_STRICT 1)")"
    printf '10) ลบคุกกี้ของจอที่เลือก\n'
    printf ' 0) กลับ\n\n'
    read -rp "เลือก: " c || on_exit
    case "$c" in
      0) return ;;
      1|4|10)
        read -rp 'หมายเลขจอ เช่น 1,3 หรือ all: ' sel || return
        if ! parse_screen_selection "$sel"; then printf '%sหมายเลขจอไม่ถูกต้อง%s\n' "$R" "$N"; pause; continue; fi
        case "$c" in
          1) cookie_set_screens ;;
          4) cookie_login_screens ;;
          10) for idx in "${SELECTED[@]}"; do cookie_delete "${PKGS[$idx]}"; done; echo "ลบแล้ว" ;;
        esac
        pause ;;
      2) cookie_import_file; pause ;;
      3) echo; cookie_check_all; pause ;;
      5)
        miss=""
        for p in "${PKGS[@]}"; do
          [ "$(screen_enabled "$p")" = "1" ] && [ ! -s "$CFG/cookie.$p" ] && miss="$miss $p"
        done
        if [ -n "$miss" ]; then printf '%s⚠ จอที่ยังไม่มีคุกกี้ (จะเปิดด้วยบัญชีเดิมในแอป):%s%s\n' "$Y" "$miss" "$N"; fi
        cfg_set COOKIE_AUTOLOGIN 1
        menu_same ;;
      6) cookie_test ;;
      7) if [ "$(cfg_get COOKIE_AUTOLOGIN 1)" = "1" ]; then cfg_set COOKIE_AUTOLOGIN 0; else cfg_set COOKIE_AUTOLOGIN 1; fi ;;
      8) if [ "$(cfg_get ALIVE_METHOD auto)" = cookie ]; then cfg_set ALIVE_METHOD auto; else cfg_set ALIVE_METHOD cookie; fi ;;
      9) if [ "$(cfg_get RJ_STRICT 1)" = "1" ]; then cfg_set RJ_STRICT 0; else cfg_set RJ_STRICT 1; fi ;;
    esac
  done
}
SCRIPTS_DIR="$BASE/scripts"
AE_TARGET=""; AE_COUNT=0; AE_ERR=""; AE_PICK=""
mkdir -p "$SCRIPTS_DIR"
ae_has_scripts() {
  local f
  for f in "$SCRIPTS_DIR"/*.lua "$SCRIPTS_DIR"/*.txt; do [ -f "$f" ] && return 0; done
  return 1
}
ae_count() {
  local f n=0
  for f in "$SCRIPTS_DIR"/*.lua "$SCRIPTS_DIR"/*.txt; do [ -f "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}
ae_root_ok() { [ "$(cfg_get USE_ROOT 0)" = "1" ] && have_su; }
ae_path_ok() { case "$1" in *\'*|*\"*|*\\*|*'$'*|*'`'*|*$'\n'*) return 1 ;; esac; [ -n "$1" ]; }
AE_HOW=""
ae_find_dir() {
  local pkg="$1" d b c out
  AE_TARGET=""; AE_HOW=""
  d=$(cfg_get "aedir.$pkg")
  if [ -n "$d" ]; then
    AE_TARGET="$d"; AE_HOW="manual"; return 0
  fi
  for b in /sdcard /storage/emulated/0; do
    for c in "$b/Android/data/$pkg/files/Delta/Autoexecute" \
             "$b/Android/data/$pkg/files/Autoexecute" \
             "$b/Android/data/$pkg/files/gloop/external/Autoexecute" \
             "$b/Delta/Autoexecute" "$b/Delta/autoexecute" "$b/Delta/Autoexec"; do
      if [ -d "$c" ]; then AE_TARGET="$c"; AE_HOW="user"; return 0; fi
    done
    d=$(find "$b/Android/data/$pkg" -maxdepth 7 -type d -iname 'autoexec*' 2>/dev/null | head -n 1)
    if [ -n "$d" ]; then AE_TARGET="$d"; AE_HOW="user"; return 0; fi
  done
  if ae_root_ok; then
    out=$(su_run "find /storage/emulated/0/Android/data/$pkg /data/media/0/Android/data/$pkg /storage/emulated/0/Delta /data/media/0/Delta /data/data/$pkg -maxdepth 8 -type d -iname 'autoexec*' 2>/dev/null | head -n 1")
    out="${out%%$'\n'*}"
    if [ -n "$out" ] && ae_path_ok "$out"; then AE_TARGET="$out"; AE_HOW="root"; return 0; fi
  fi
  return 1
}
ae_sync_pkg() {
  local pkg="$1" tgt man f base name old cmd out via_root=0 line
  local -a names=()
  AE_COUNT=0; AE_ERR=""
  perf_gen_lua
  if ! ae_find_dir "$pkg"; then
    AE_ERR="ไม่พบโฟลเดอร์ Autoexecute (เปิด Delta ในจอนี้ค้างไว้สักครั้งก่อน, เปิดใช้รูท หรือตั้งเองที่เมนู e ข้อ 5, ดูผลตรวจที่ข้อ 7)"
    return 1
  fi
  tgt="$AE_TARGET"
  ae_path_ok "$tgt" || { AE_ERR="path โฟลเดอร์มีอักขระที่ไม่รองรับ: $tgt"; return 1; }
  man="$STATE/ae.$pkg"
  if [ "$AE_HOW" != "root" ]; then
    mkdir -p "$tgt" 2>/dev/null
    [ -d "$tgt" ] && [ -w "$tgt" ] || via_root=1
  else
    via_root=1
  fi
  if [ "$via_root" = "1" ] && ! ae_root_ok; then
    AE_ERR="เขียนโฟลเดอร์ไม่ได้ด้วยสิทธิ์ Termux ($tgt) → เปิดใช้รูทที่ตั้งค่า ข้อ 4"
    return 1
  fi
  if [ "$(cfg_get AUTOEXEC_ON 1)" = "1" ]; then
    for f in "$SCRIPTS_DIR"/*.lua "$SCRIPTS_DIR"/*.txt; do
      [ -f "$f" ] || continue
      base=$(basename "$f")
      [ "$(cfg_get "aeoff.$base" 0)" = "1" ] && continue
      ae_for_pkg "$base" "$pkg" || continue      # สคริปต์นี้ไม่ได้กำหนดให้จอนี้
      ae_clean "$f" quiet
      names+=("$base")
    done
  fi
  if [ "$via_root" = "1" ]; then
    cmd="mkdir -p '$tgt'"
    if [ -s "$man" ]; then
      while IFS= read -r old; do [ -n "$old" ] && cmd+="; rm -f '$tgt/$old'"; done < "$man"
    fi
    for base in "${names[@]}"; do
      name="procysis_$base"
      cmd+="; cp -f '$SCRIPTS_DIR/$base' '$tgt/$name' && chmod 666 '$tgt/$name'; [ -s '$tgt/$name' ] && echo \"PROCYSIS_OK:$name\""
    done
    out=$(su_run "$cmd")
    : > "$man"
    while IFS= read -r line; do
      case "$line" in PROCYSIS_OK:*) printf '%s\n' "${line#PROCYSIS_OK:}" >> "$man"; AE_COUNT=$((AE_COUNT + 1)) ;; esac
    done <<<"$out"
  else
    if [ -s "$man" ]; then
      while IFS= read -r old; do [ -n "$old" ] && rm -f "$tgt/$old" 2>/dev/null; done < "$man"
    fi
    : > "$man"
    for base in "${names[@]}"; do
      name="procysis_$base"
      if cp -f "$SCRIPTS_DIR/$base" "$tgt/$name" 2>/dev/null && [ -s "$tgt/$name" ]; then
        printf '%s\n' "$name" >> "$man"; AE_COUNT=$((AE_COUNT + 1))
      fi
    done
  fi
  if [ "$AE_COUNT" -lt "${#names[@]}" ]; then
    AE_ERR="วางสำเร็จ $AE_COUNT จาก ${#names[@]} ไฟล์ ($tgt) $([ "$via_root" = "1" ] && echo '[root]' || echo '[ปกติ]')"
    log WARN "$pkg autoexec $AE_ERR"
    return 1
  fi
  log INFO "$pkg autoexec วาง $AE_COUNT ไฟล์ -> $tgt ($([ "$via_root" = "1" ] && echo root || echo user))"
  return 0
}
AE_FIXED=0
ae_clean() {
  local f="$1" n
  AE_FIXED=0
  [ -f "$f" ] || return 0
  n=$(LC_ALL=C grep -c -e $'\xE2\x80\x9C' -e $'\xE2\x80\x9D' -e $'\xE2\x80\x9E' -e $'\xE2\x80\x9F' \
        -e $'\xE2\x80\x98' -e $'\xE2\x80\x99' -e $'\xE2\x80\x9A' -e $'\xE2\x80\x9B' \
        -e $'\xE2\x80\x8B' -e $'\xE2\x80\x8C' -e $'\xE2\x80\x8D' -e $'\xEF\xBB\xBF' -e $'\xC2\xA0' "$f" 2>/dev/null)
  [ "${n:-0}" -gt 0 ] || return 0
  LC_ALL=C sed -i \
    -e $'s/\xE2\x80[\x9C\x9D\x9E\x9F]/"/g' \
    -e $'s/\xE2\x80[\x98\x99\x9A\x9B]/\'/g' \
    -e $'s/\xE2\x80[\x8B\x8C\x8D]//g' \
    -e $'s/\xEF\xBB\xBF//g' \
    -e $'s/\xC2\xA0/ /g' "$f"
  AE_FIXED="$n"
  log INFO "ล้างอักขระผิดในสคริปต์ $(basename "$f"): $n บรรทัด"
  [ "$2" = "quiet" ] || printf '   %s🧹 แก้เครื่องหมายคำพูดโค้ง/อักขระล่องหน %s บรรทัด%s\n' "$Y" "$n" "$N"
  return 0
}
AE_LINES=0; AE_BYTES=0
ae_paste() {
  local dest="$1" line old_stty out ch i
  AE_LINES=0; AE_BYTES=0
  old_stty=$(stty -g 2>/dev/null)
  stty -icanon echo min 1 time 0 2>/dev/null     # ปิด canonical (กันตัดบรรทัดยาว) แต่ยังโชว์ตัวอักษรที่พิมพ์/วาง
  : > "$dest"
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    if [[ "$line" == *$'\177'* || "$line" == *$'\b'* ]]; then
      out=""
      for ((i = 0; i < ${#line}; i++)); do
        ch="${line:i:1}"
        if [[ "$ch" == $'\177' || "$ch" == $'\b' ]]; then out="${out%?}"; else out+="$ch"; fi
      done
      line="$out"
    fi
    if [[ "$line" == *$'\004'* ]]; then
      line="${line//$'\004'/}"
      [ -n "$line" ] && { printf '%s\n' "$line" >> "$dest"; AE_LINES=$((AE_LINES + 1)); }
      break
    fi
    [ "$line" = "EOF" ] && break
    printf '%s\n' "$line" >> "$dest"
    AE_LINES=$((AE_LINES + 1))
  done
  if [ -n "$old_stty" ]; then stty "$old_stty" 2>/dev/null; else stty sane 2>/dev/null; fi
  AE_BYTES=$(stat -c %s "$dest" 2>/dev/null || echo 0)
}
ae_for_pkg() {
  local t; t=$(cfg_get "aeto.$1")
  [ -z "$t" ] && return 0
  case " $t " in *" $2 "*) return 0 ;; esac
  return 1
}
ae_target_text() {
  local t p i out=""
  t=$(cfg_get "aeto.$1")
  if [ -z "$t" ]; then printf 'ทุกจอ'; return; fi
  i=0
  for p in "${PKGS[@]}"; do
    i=$((i + 1))
    case " $t " in *" $p "*) out="${out:+$out,}$i" ;; esac
  done
  printf 'จอ %s' "${out:-(ไม่พบจอที่กำหนด)}"
}
ae_list() {
  local f base st n=0 sz
  [ "${#PKGS[@]}" -gt 0 ] || mapfile -t PKGS < <(detect_pkgs)
  printf '\n%sสคริปต์ที่เก็บไว้%s (%s)\n' "$C" "$N" "$SCRIPTS_DIR"
  for f in "$SCRIPTS_DIR"/*.lua "$SCRIPTS_DIR"/*.txt; do
    [ -f "$f" ] || continue
    n=$((n + 1)); base=$(basename "$f")
    sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
    if [ "$(cfg_get "aeoff.$base" 0)" = "1" ]; then st="${Y}ปิด${N}"; else st="${G}เปิด${N}"; fi
    printf '  %s) %s  [%s]  %s ไบต์  → %s\n' "$n" "$base" "$st" "$sz" "$(ae_target_text "$base")"
  done
  [ "$n" -eq 0 ] && printf '  %s— ยังไม่มีสคริปต์ (เพิ่มที่ข้อ 1)%s\n' "$DIM" "$N"
}
ae_assign() {
  local n base sel idx t=""
  read -rp 'หมายเลขสคริปต์: ' n || return
  if ! ae_pick "$n"; then printf '%sหมายเลขไม่ถูกต้อง%s\n' "$R" "$N"; return; fi
  base=$(basename "$AE_PICK")
  mapfile -t PKGS < <(detect_pkgs)
  if [ -z "${PKGS[0]:-}" ]; then printf '%s✗ ไม่พบแพ็กเกจ%s\n' "$R" "$N"; return; fi
  show_screen_list
  printf '\nวาง %s ที่จอไหน (เช่น 1,3 | all = ทุกจอ) : ' "$base"
  read -r sel || return
  sel="${sel//$'\r'/}"
  if [ "$sel" = "all" ]; then
    rm -f "$CFG/aeto.$base"; printf '%s✓ %s → ทุกจอ%s\n' "$G" "$base" "$N"; return
  fi
  if ! parse_screen_selection "$sel"; then printf '%sหมายเลขจอไม่ถูกต้อง%s\n' "$R" "$N"; return; fi
  for idx in "${SELECTED[@]}"; do t="${t:+$t }${PKGS[$idx]}"; done
  cfg_set "aeto.$base" "$t"
  printf '%s✓ %s → %s%s\n' "$G" "$base" "$(ae_target_text "$base")" "$N"
  printf '%s  ซิงก์ที่ข้อ 4 หรือเข้าเกมใหม่ สคริปต์ที่ไม่ใช่ของจอนั้นจะถูกลบออกจากโฟลเดอร์ให้เอง%s\n' "$DIM" "$N"
  log INFO "กำหนดสคริปต์ $base -> $t"
}
ae_pick() {
  local n="$1" i=0 f
  AE_PICK=""
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  for f in "$SCRIPTS_DIR"/*.lua "$SCRIPTS_DIR"/*.txt; do
    [ -f "$f" ] || continue
    i=$((i + 1))
    if [ "$i" -eq "$((10#$n))" ]; then AE_PICK="$f"; return 0; fi
  done
  return 1
}
ae_add() {
  local mode name dest src url line n=0
  printf '\n 1) วางโค้ดสคริปต์ (จบด้วยการพิมพ์ EOF ในบรรทัดใหม่)\n'
  printf ' 2) คัดลอกจากไฟล์ในเครื่อง\n'
  printf ' 3) ใส่ลิงก์สคริปต์ (สร้างบรรทัด loadstring ให้)\n'
  printf ' 0) ยกเลิก\n\n'
  read -rp "เลือก: " mode || return
  case "$mode" in 1|2|3) ;; *) return ;; esac
  ask "ชื่อสคริปต์ (ตัวอักษร/ตัวเลข ไม่ต้องใส่นามสกุล)" "script$(( $(ae_count) + 1 ))"
  name=$(printf '%s' "$REPLY_VAL" | tr -c 'A-Za-z0-9._-' '_' | sed 's/\.\(lua\|txt\)$//')
  [ -n "$name" ] || { printf '%s✗ ชื่อไม่ถูกต้อง%s\n' "$R" "$N"; return; }
  dest="$SCRIPTS_DIR/$name.lua"
  case "$mode" in
    1) printf 'วางโค้ดได้เลย แล้วพิมพ์ EOF (ขึ้นบรรทัดใหม่) เพื่อจบ:\n'
       ae_paste "$dest"; n="$AE_LINES" ;;
    2) ask "path ไฟล์สคริปต์ (เช่น /sdcard/Download/a.lua)" ""
       src="$REPLY_VAL"
       if [ ! -r "$src" ]; then printf '%s✗ อ่านไฟล์ไม่ได้%s\n' "$R" "$N"; return; fi
       cp -f "$src" "$dest"; n=$(grep -c '' "$dest") ;;
    3) ask "ลิงก์สคริปต์ (https://...)" ""
       url="${REPLY_VAL//$'\r'/}"
       case "$url" in http://*|https://*) ;; *) printf '%s✗ ลิงก์ต้องขึ้นต้นด้วย http/https%s\n' "$R" "$N"; return ;; esac
       case "$url" in *\"*|*\'*|*" "*|*\\*) printf '%s✗ ลิงก์มีอักขระที่ไม่รองรับ%s\n' "$R" "$N"; return ;; esac
       printf 'loadstring(game:HttpGet("%s"))()\n' "$url" > "$dest"; n=1 ;;
  esac
  if [ ! -s "$dest" ]; then rm -f "$dest"; printf '%s✗ สคริปต์ว่าง ไม่บันทึก%s\n' "$R" "$N"; return; fi
  ae_clean "$dest"
  rm -f "$CFG/aeoff.$name.lua"
  printf '%s✓ บันทึก %s.lua แล้ว (%s บรรทัด)%s\n' "$G" "$name" "$n" "$N"
  printf '   ขนาดไฟล์ %s ไบต์ | ขึ้นต้น: %s\n' "$(stat -c %s "$dest" 2>/dev/null)" "$(head -c 70 "$dest" | tr '\n' ' ')"
  log INFO "เพิ่มสคริปต์ autoexec: $name.lua"
}
ae_targets() {
  local p i=0
  banner; load_pkgs || return
  printf '\n%sโฟลเดอร์ Autoexecute ของแต่ละจอ%s\n' "$C" "$N"
  for p in "${PKGS[@]}"; do
    i=$((i + 1))
    printf '\n%s%s) %s%s\n' "$Y" "$i" "$p" "$N"
    if ae_find_dir "$p"; then
      printf '   ตอนนี้: %s%s%s%s\n' "$G" "$AE_TARGET" "$N" "$([ -n "$(cfg_get "aedir.$p")" ] && echo ' (ตั้งเอง)')"
    else
      printf '   %sไม่พบ เปิด Delta ในจอนี้ค้างไว้สักครั้งแล้วลองใหม่ หรือพิมพ์ path เอง%s\n' "$R" "$N"
    fi
    ask "   path ใหม่ (Enter=คงเดิม | -=ใช้ตรวจอัตโนมัติ)" "$(cfg_get "aedir.$p")"
    if [ -z "$REPLY_VAL" ]; then rm -f "$CFG/aedir.$p"; else cfg_set "aedir.$p" "$REPLY_VAL"; fi
  done
  pause
}
ae_sync_all() {
  local p
  banner; load_pkgs || return
  for p in "${PKGS[@]}"; do
    [ "$(screen_enabled "$p")" = "1" ] || continue
    printf '\n%s%s%s\n' "$C" "$p" "$N"
    if ae_sync_pkg "$p"; then
      printf '  %s✓ วางสคริปต์ %s ไฟล์%s → %s\n' "$G" "$AE_COUNT" "$N" "$AE_TARGET"
    else
      printf '  %s✗ %s%s\n' "$R" "$AE_ERR" "$N"
    fi
  done
  pause
}
ae_diag() {
  local p i=0 how ls_out nm man have miss
  banner; load_pkgs || return
  printf '\n%sตรวจ Auto Execute%s\n' "$C" "$N"
  printf ' สคริปต์ที่เก็บไว้: %s ไฟล์ | ระบบ: %s | รูท: %s\n' "$(ae_count)" "$(onoff "$(cfg_get AUTOEXEC_ON 1)")" "$(ae_root_ok && echo พร้อม || echo 'ไม่พร้อม/ปิด')"
  for p in "${PKGS[@]}"; do
    i=$((i + 1))
    printf '\n%s%s) %s%s\n' "$Y" "$i" "$p" "$N"
    if ! ae_find_dir "$p"; then
      printf '   %s✗ ไม่พบโฟลเดอร์ Autoexecute%s\n' "$R" "$N"
      printf '   %s- เปิด Delta ในจอนี้ค้างไว้สักครั้ง (ให้ Delta สร้างโฟลเดอร์ก่อน)\n   - ถ้าเป็น Android 11+ ต้องเปิดใช้รูท (ตั้งค่า ข้อ 4)\n   - หรือพิมพ์ path เองที่เมนู e ข้อ 5%s\n' "$DIM" "$N"
      continue
    fi
    case "$AE_HOW" in manual) how="ตั้งเอง" ;; root) how="ค้นด้วย root" ;; *) how="ตรวจเจออัตโนมัติ" ;; esac
    printf '   โฟลเดอร์: %s%s%s (%s)\n' "$G" "$AE_TARGET" "$N" "$how"
    if [ "$AE_HOW" != "root" ] && [ -d "$AE_TARGET" ]; then
      printf '   สิทธิ์เขียน: %s\n' "$([ -w "$AE_TARGET" ] && echo 'ได้ (สิทธิ์ปกติ)' || echo 'ไม่ได้ → ต้องใช้ root')"
      ls_out=$(ls -1 "$AE_TARGET" 2>/dev/null)
    elif ae_root_ok && ae_path_ok "$AE_TARGET"; then
      printf '   สิทธิ์เขียน: ใช้ root\n'
      ls_out=$(su_run "ls -1 '$AE_TARGET' 2>/dev/null")
    else
      printf '   %s✗ มองโฟลเดอร์นี้ไม่เห็นด้วยสิทธิ์ปกติ และ root ไม่พร้อม%s\n' "$R" "$N"
      ls_out=""
    fi
    printf '   ไฟล์ในโฟลเดอร์ตอนนี้:\n'
    if [ -n "$ls_out" ]; then printf '%s\n' "$ls_out" | head -n 15 | sed 's/^/     • /'; else printf '     %s(ว่าง/อ่านไม่ได้)%s\n' "$DIM" "$N"; fi
    man="$STATE/ae.$p"; miss=0
    if [ -s "$man" ]; then
      while IFS= read -r nm; do
        [ -n "$nm" ] || continue
        if grep -qxF "$nm" <<<"$ls_out"; then have="${G}มี${N}"; else have="${R}ไม่เจอ${N}"; miss=$((miss + 1)); fi
        printf '   ที่เคยวางไว้: %s → %s\n' "$nm" "$have"
      done < "$man"
    else
      printf '   %sยังไม่เคยวางสคริปต์จอนี้ (ซิงก์ที่ข้อ 4 หรือเปิดเกมจากสคริปต์)%s\n' "$DIM" "$N"
    fi
    [ "$miss" -gt 0 ] && printf '   %s⚠ ไฟล์ที่วางไว้หาย แปลว่าโฟลเดอร์นี้อาจไม่ใช่ที่ Delta ใช้จริง ลองข้อ 5%s\n' "$Y" "$N"
  done
  printf '\n%sถ้าไฟล์อยู่ครบแต่เข้าเกมแล้วสคริปต์ไม่รัน: เช็คว่าเปิด Auto Execute ในตัว Delta แล้ว และลองเพิ่ม "สคริปต์ทดสอบ" (ข้อ 8) ดูว่าเห็นแจ้งเตือนในเกมไหม%s\n' "$DIM" "$N"
  pause
}
ae_add_test() {
  local dest="$SCRIPTS_DIR/test.lua"
  cat > "$dest" <<'LUA'
-- PROCYSIS: สคริปต์ทดสอบ Auto Execute (ลบได้เมื่อทดสอบเสร็จ)
pcall(function()
  game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "PROCYSIS",
    Text = "Auto Execute ทำงานแล้ว",
    Duration = 15,
  })
end)
print("[PROCYSIS] Auto Execute ทำงานแล้ว")
LUA
  rm -f "$CFG/aeoff.test.lua"
  printf '%s✓ เพิ่ม test.lua แล้ว (จะถูกวางเป็น procysis_test.lua)%s\n' "$G" "$N"
  printf '  ซิงก์ที่ข้อ 4 หรือเข้าเกมตามปกติ แล้วดูว่ามีแจ้งเตือน "Auto Execute ทำงานแล้ว" ขึ้นในเกมไหม\n'
  printf '  %sเห็นแจ้งเตือน = ระบบวางไฟล์/รันถูกต้อง ปัญหาอยู่ที่ตัวสคริปต์ของมารุ (เช่นต้องใส่คีย์ของสคริปต์นั้น หรือรองรับเฉพาะบางเกม)%s\n' "$DIM" "$N"
  log INFO "เพิ่มสคริปต์ทดสอบ autoexec"
}
menu_autoexec() {
  local c n base
  while true; do
    banner
    printf '%sAuto Execute (รันสคริปต์เองทุกครั้งที่เข้าเกม)%s\n' "$Y" "$N"
    ae_list
    printf '\n 1) เพิ่มสคริปต์\n'
    printf ' 2) เปิด/ปิดสคริปต์รายตัว\n'
    printf ' 3) ลบสคริปต์\n'
    printf ' 4) ซิงก์ไปทุกจอตอนนี้\n'
    printf ' 5) ตั้ง/ดูโฟลเดอร์ Autoexecute รายจอ\n'
    printf ' 6) วางสคริปต์ให้อัตโนมัติก่อนเปิดเกมทุกครั้ง : %s\n' "$(onoff "$(cfg_get AUTOEXEC_ON 1)")"
    printf ' 7) ตรวจสอบ/วินิจฉัย Auto Execute (ดูว่าไฟล์ถึงโฟลเดอร์จริงไหม)\n'
    printf ' 8) เพิ่มสคริปต์ทดสอบ (ขึ้นแจ้งเตือนในเกม)\n'
    printf ' 9) กำหนดว่าสคริปต์ไหนไปจอไหน (แยกบัญชี/คีย์ต่อจอ)\n'
    printf ' 0) กลับ\n\n'
    printf '%sสคริปต์จะถูกวางลงโฟลเดอร์ก่อนเปิดแอป และ Delta ต้องเปิดฟีเจอร์ Auto Execute ไว้ด้วย%s\n\n' "$DIM" "$N"
    read -rp "เลือก: " c || on_exit
    case "$c" in
      1) ae_add; pause ;;
      2|3)
        read -rp 'หมายเลขสคริปต์: ' n || continue
        if ! ae_pick "$n"; then printf '%sหมายเลขไม่ถูกต้อง%s\n' "$R" "$N"; pause; continue; fi
        base=$(basename "$AE_PICK")
        if [ "$c" = "2" ]; then
          if [ "$(cfg_get "aeoff.$base" 0)" = "1" ]; then rm -f "$CFG/aeoff.$base"; echo "เปิดใช้งานแล้ว"
          else cfg_set "aeoff.$base" 1; echo "ปิดใช้งานแล้ว"; fi
        else
          if confirm "ลบ $base ?"; then rm -f "$AE_PICK" "$CFG/aeoff.$base"; echo "ลบแล้ว"; log INFO "ลบสคริปต์ autoexec: $base"; fi
        fi
        pause ;;
      4) ae_sync_all ;;
      5) ae_targets ;;
      6) if [ "$(cfg_get AUTOEXEC_ON 1)" = "1" ]; then cfg_set AUTOEXEC_ON 0; else cfg_set AUTOEXEC_ON 1; fi ;;
      7) ae_diag ;;
      8) ae_add_test; pause ;;
      9) ae_assign; pause ;;
      0) return ;;
    esac
  done
}
menu_same() {
  local uri p rp rv
  banner; load_pkgs || return
  echo
  ask "Game ID (หรือวางลิงก์เกม)" "$(cfg_get PLACE_ID)"; rp="$REPLY_VAL"
  ask "ลิงก์ VIP Server (ไม่มีพิมพ์ -)" "$(cfg_get VIP_LINK)"; rv="$REPLY_VAL"
  resolve_inputs "$rp" "$rv"
  uri=$(valid_uri "$(build_uri "$IN_PLACE" "$IN_VIP")")
  if [ -z "$uri" ]; then
    printf '%s✗ Game ID / ลิงก์ VIP ไม่ถูกต้อง%s\n' "$R" "$N"
    log ERROR "เมนู 1: Game ID/VIP ไม่ถูกต้อง"; pause; return
  fi
  case "$uri" in
    *linkCode=*)               printf '   %sโหมด: VIP Server (privateServerLinkCode)%s\n' "$G" "$N" ;;
    *navigation/share_links*)  printf '   %sโหมด: VIP Server (ลิงก์แชร์)%s\n' "$G" "$N" ;;
    *)                         printf '   %sโหมด: เซิร์ฟสาธารณะ (Game ID)%s\n' "$C" "$N" ;;
  esac
  cfg_set PLACE_ID "$IN_PLACE"; cfg_set VIP_LINK "$IN_VIP"
  URIS=()
  for p in "${PKGS[@]}"; do URIS+=("$uri"); done
  run_batch "เข้าเกมเหมือนกันทุกจอ"; pause
}
menu_separate() {
  local p uri rp rv
  banner; load_pkgs || return
  URIS=()
  for p in "${PKGS[@]}"; do
    printf '\n%s📦 %s%s\n' "$Y" "$p" "$N"
    ask "  Game ID (หรือวางลิงก์เกม)" "$(cfg_get "place.$p" "$(cfg_get PLACE_ID)")"; rp="$REPLY_VAL"
    ask "  ลิงก์ VIP Server (ไม่มีพิมพ์ -)" "$(cfg_get "vip.$p" "$(cfg_get VIP_LINK)")"; rv="$REPLY_VAL"
    resolve_inputs "$rp" "$rv"
    cfg_set "place.$p" "$IN_PLACE"; cfg_set "vip.$p" "$IN_VIP"
    uri=$(valid_uri "$(build_uri "$IN_PLACE" "$IN_VIP")")
    if [ -z "$uri" ]; then
      printf '  %s⚠ ไม่มี/ไม่ถูกต้อง -> จอนี้จะเปิดแอปเฉยๆ%s\n' "$Y" "$N"
      log WARN "$p: Game ID/VIP ว่างหรือไม่ถูกต้อง เปิดแอปเฉยๆ"
    fi
    URIS+=("$uri")
  done
  run_batch "เข้าเกมแยกแพ็กเกจ"; pause
}
menu_open() {
  local p
  banner; load_pkgs || return
  URIS=()
  for p in "${PKGS[@]}"; do URIS+=(""); done
  run_batch "เปิด Roblox ทุกจอที่เปิดใช้งาน"; pause
}
menu_screen_control() {
  local action selection idx pkg
  while true; do
    banner
    printf '%s╭─ จัดการเปิด / ปิด Roblox รายจอ ─╮%s\n' "$C" "$N"
    load_pkgs || return
    show_screen_list
    printf '\n 1) เปิดแอปจอที่เลือก\n'
    printf ' 2) ปิดแอปจอที่เลือก (Force Stop)\n'
    printf ' 3) เปิดใช้งานจอในระบบจัดการ\n'
    printf ' 4) ปิดใช้งานจอในระบบจัดการ\n'
    printf ' 0) กลับเมนูหลัก\n\n'
    read -rp 'เลือกเมนู: ' action || return
    case "$action" in 0) return ;; 1|2|3|4) ;; *) echo 'กรุณาเลือก 0-4'; sleep 1; continue ;; esac
    read -rp 'หมายเลขจอ เช่น 1,3,5 หรือ all: ' selection || return
    if ! parse_screen_selection "$selection"; then
      printf '%sหมายเลขจอไม่ถูกต้อง%s\n' "$R" "$N"; pause; continue
    fi
    for idx in "${SELECTED[@]}"; do
      pkg="${PKGS[$idx]}"
      printf '\n%sจอ %s: %s%s\n' "$C" "$((idx+1))" "$pkg" "$N"
      case "$action" in
        1)
          if launch_smart "$pkg" ""; then
            printf '%sส่งคำสั่งเปิดแล้ว%s\n' "$G" "$N"
            set_state "$pkg" OK "manual-open"; stat_set "$pkg" start "$(date +%s)"; log INFO "สั่งเปิดรายจอ: $pkg"
          else
            printf '%sเปิดไม่สำเร็จ (ดู Log)%s\n' "$R" "$N"
            set_state "$pkg" FAIL "manual-open"
          fi ;;
        2)
          if am force-stop "$pkg" >/dev/null 2>&1; then
            printf '%sส่งคำสั่ง Force Stop แล้ว%s\n' "$G" "$N"
            set_state "$pkg" STOP "manual-stop"; log INFO "สั่งปิดรายจอ: $pkg"
          else
            printf '%sส่งคำสั่งปิดไม่สำเร็จ%s\n' "$R" "$N"
            log ERROR "สั่งปิดรายจอไม่สำเร็จ: $pkg"
          fi ;;
        3)
          cfg_set "enabled.$pkg" 1
          printf '%sเปิดใช้งานในระบบจัดการแล้ว%s\n' "$G" "$N" ;;
        4)
          cfg_set "enabled.$pkg" 0
          printf '%sปิดใช้งานในระบบจัดการแล้ว%s\n' "$Y" "$N" ;;
      esac
    done
    pause
  done
}
menu_webhook() {
  local c url n i
  while true; do
    banner
    url=$(cfg_get WEBHOOK_URL)
    if [ -n "$url" ]; then n="ตั้งค่าแล้ว"; else n="ยังไม่ตั้งค่า"; fi
    printf '%sWebhook แจ้งข้อมูล%s [%s]\n\n' "$Y" "$N" "$n"
    printf ' 1) ตั้งค่า / เปลี่ยน Webhook URL\n'
    printf ' 2) ส่งสถานะตอนนี้\n'
    printf ' 3) ส่งอัตโนมัติทุก N นาที (Ctrl+C หยุด)\n'
    printf ' 4) ลบ Webhook URL\n'
    printf ' 5) ล้างสถิติรายจอ (ตัวนับรีจอย/เวลารัน)\n'
    printf ' 6) ส่งรายงานรอบอัตโนมัติระหว่างเฝ้าจอ : ทุก %s นาที (0=ปิด)\n' "$(cfg_get RJ_REPORT 0)"
    printf ' 0) กลับ\n\n'
    read -rp "เลือก: " c || on_exit
    case "$c" in
      1)
        ask "วาง Webhook URL" "$url"
        if [ -z "$REPLY_VAL" ]; then :
        elif [[ "$REPLY_VAL" == https://* || "$REPLY_VAL" == http://* ]]; then
          cfg_set WEBHOOK_URL "$REPLY_VAL"
          mapfile -t PKGS < <(detect_pkgs)
          printf 'ส่งข้อความทดสอบ...'
          if send_status "ทดสอบ" ""; then printf ' %s✓ สำเร็จ%s\n' "$G" "$N"; else printf ' %s✗ ไม่สำเร็จ (ตรวจ URL / อินเทอร์เน็ต)%s\n' "$R" "$N"; fi
        else printf '%s✗ URL ต้องขึ้นต้นด้วย http หรือ https%s\n' "$R" "$N"; fi
        pause ;;
      2)
        if [ -z "$url" ]; then printf '%sยังไม่ได้ตั้ง Webhook URL%s\n' "$R" "$N"
        else mapfile -t PKGS < <(detect_pkgs); printf 'กำลังส่ง...'
          if send_status "สถานะ" ""; then printf ' %s✓ สำเร็จ%s\n' "$G" "$N"; else printf ' %s✗ ไม่สำเร็จ (ดู Log)%s\n' "$R" "$N"; fi
        fi
        pause ;;
      3)
        if [ -z "$url" ]; then printf '%sยังไม่ได้ตั้ง Webhook URL%s\n' "$R" "$N"; pause; continue; fi
        ask "ส่งทุกกี่นาที" "5"; n="$REPLY_VAL"
        case "$n" in ''|*[!0-9]*|0) n=5 ;; esac
        STOP=0; trap 'STOP=1' INT
        printf '\nเริ่มส่งทุก %s นาที (กด Ctrl+C เพื่อหยุด)\n' "$n"
        log INFO "เริ่มส่ง Webhook อัตโนมัติทุก $n นาที"
        while [ "$STOP" -eq 0 ]; do
          mapfile -t PKGS < <(detect_pkgs)
          if send_status "รายงานอัตโนมัติ" ""; then printf '[%s] ส่งแล้ว\n' "$(date +%T)"
          else printf '[%s] ส่งไม่สำเร็จ\n' "$(date +%T)"; fi
          i=0
          while [ "$i" -lt $((n*60)) ] && [ "$STOP" -eq 0 ]; do sleep 1; i=$((i+1)); done
        done
        trap on_int INT
        log INFO "หยุดส่ง Webhook อัตโนมัติ"; pause ;;
      4) rm -f "$CFG/WEBHOOK_URL"; echo "ลบแล้ว"; sleep 1 ;;
      5) if confirm "ล้างสถิติรีจอย/เวลารันทุกจอ?"; then stats_reset; echo "ล้างแล้ว"; fi; sleep 1 ;;
      6) set_num RJ_REPORT "ส่งรายงานทุกกี่นาที (0=ปิด)" 0 0 ;;
      0) return ;;
    esac
  done
}
colorize_log() { sed -e "s/\[ERROR\]/${R}[ERROR]${N}/" -e "s/\[WARN\]/${Y}[WARN]${N}/" -e "s/\[INFO\]/${G}[INFO]${N}/"; }
menu_log() {
  local c
  while true; do
    banner
    printf '%sLog บันทึกผลและบัค%s\n' "$Y" "$N"
    printf 'ไฟล์: %s\n\n' "$LOG_FILE"
    printf ' 1) ดู 40 บรรทัดล่าสุด\n 2) ดูเฉพาะ ERROR / WARN\n 3) ล้าง Log\n 0) กลับ\n\n'
    read -rp "เลือก: " c || on_exit
    case "$c" in
      1) echo; tail -n 40 "$LOG_FILE" | colorize_log; pause ;;
      2) echo; grep -E '\[(ERROR|WARN)\]' "$LOG_FILE" | tail -n 40 | colorize_log; pause ;;
      3) : > "$LOG_FILE"; rm -f "$LOG_FILE.old"; log INFO "ล้าง Log"; echo "ล้างแล้ว"; sleep 1 ;;
      0) return ;;
    esac
  done
}
menu_settings() {
  local c
  while true; do
    banner
    printf '%sตั้งค่า%s\n\n' "$Y" "$N"
    printf ' 1) ล้างแคชอัตโนมัติก่อนเปิดเกม : %s\n' "$(onoff "$(cfg_get AUTO_CLEAR 1)")"
    printf ' 2) หน่วงเวลาระหว่างจอ : %s วิ\n' "$(cfg_get LAUNCH_DELAY 20)"
    printf ' 3) คำค้นชื่อแพ็กเกจ : %s\n' "$(cfg_get PKG_FILTER roblox)"
    printf ' 4) ใช้รูทช่วยล้างแคชภายใน : %s (ต้องมีสิทธิ์ Root จริง)\n' "$(onoff "$(cfg_get USE_ROOT 0)")"
    printf ' 0) กลับ\n\n'
    read -rp "เลือก: " c || on_exit
    case "$c" in
      1) if [ "$(cfg_get AUTO_CLEAR 1)" = "1" ]; then cfg_set AUTO_CLEAR 0; else cfg_set AUTO_CLEAR 1; fi ;;
      2) ask "หน่วงกี่วินาที" "$(cfg_get LAUNCH_DELAY 20)"
         case "$REPLY_VAL" in ''|*[!0-9]*) ;; *) cfg_set LAUNCH_DELAY "$REPLY_VAL" ;; esac ;;
      3) ask "คำค้น (regex เช่น roblox|rblx)" "$(cfg_get PKG_FILTER roblox)"
         [ -n "$REPLY_VAL" ] && cfg_set PKG_FILTER "$REPLY_VAL" ;;
      4) if [ "$(cfg_get USE_ROOT 0)" = "1" ]; then
           cfg_set USE_ROOT 0; rootsh_stop
         else
           cfg_set USE_ROOT 1
           if have_su; then
             printf '%s⏳ กำลังเชื่อมต่อ root (ครั้งแรกอาจช้า กดอนุญาตถ้ามีหน้าต่างเด้ง)...%s\n' "$DIM" "$N"
             if rootsh_start; then printf ' %s✓ พร้อมใช้งาน%s\n' "$G" "$N"; else printf ' %s✗ ใช้ root ไม่ได้ (ลองเมนู a ข้อ 10)%s\n' "$R" "$N"; fi
             sleep 1
           fi
         fi ;;
      0) return ;;
    esac
  done
}
STATS="$STATE/stats"; REJOIN_LOG="$STATE/rejoin.log"
mkdir -p "$STATS"
stat_get() { if [ -s "$STATS/$1.$2" ]; then cat "$STATS/$1.$2"; else printf '%s' "${3:-0}"; fi; }
stat_set() { printf '%s' "$3" > "$STATS/$1.$2"; }
stat_inc() {
  local v; v=$(stat_get "$1" "$2" 0)
  case "$v" in ''|*[!0-9]*) v=0 ;; esac
  stat_set "$1" "$2" "$((v + 1))"
}
hline() { printf '%*s' "$2" '' | sed "s/ /$1/g"; }
tail_str() { local s="$1" n="$2"; if [ "${#s}" -gt "$n" ]; then printf '%s' "${s: -$n}"; else printf '%s' "$s"; fi; }
utf8_len() { printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | wc -c; }
fmt_dur() {
  local s="${1:-0}" d h m
  case "$s" in ''|*[!0-9]*) s=0 ;; esac
  d=$((s / 86400)); h=$(((s % 86400) / 3600)); m=$(((s % 3600) / 60))
  if [ "$d" -gt 0 ]; then printf '%sd %sh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%sh %02dm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%sm' "$m"
  else printf '%ss' "$s"; fi
}
rejoin_note() {
  local now; now=$(date +%s)
  printf '%s|%s|%s\n' "$now" "$1" "$2" >> "$REJOIN_LOG"
  stat_inc "$1" rejoins; stat_set "$1" last_rejoin "$now"; stat_set "$1" last_reason "$2"
  if [ "$(wc -l < "$REJOIN_LOG" 2>/dev/null || echo 0)" -gt 600 ]; then
    tail -n 300 "$REJOIN_LOG" > "$REJOIN_LOG.tmp" && mv -f "$REJOIN_LOG.tmp" "$REJOIN_LOG"
  fi
}
rejoin_count_hr() {
  awk -F'|' -v p="$1" -v t="$(( $(date +%s) - 3600 ))" '$2==p && $1+0>=t {n++} END{print n+0}' "$REJOIN_LOG" 2>/dev/null || echo 0
}
stats_reset() { rm -f "$STATS"/* "$REJOIN_LOG" 2>/dev/null; log INFO "ล้างสถิติรายจอ"; }
pkg_uptime() {
  local st; st=$(stat_get "$1" start 0)
  case "$st" in ''|*[!0-9]*|0) printf -- '-'; return ;; esac
  fmt_dur $(( $(date +%s) - st ))
}
alive_file_mark() {
  local f="$STATE/alive.$1" a m ts iv age
  [ -s "$f" ] || return 1
  iv=$(cfg_get RJ_INTERVAL 45)
  IFS='|' read -r a m ts < "$f"
  age=$(( $(date +%s) - ${ts:-0} ))
  [ "$age" -le $((iv * 3 + 30)) ] || return 1
  case "$a" in 0) printf '🟢' ;; 1) printf '🔴' ;; G) printf '⏳' ;; 2) printf '❔' ;; *) return 1 ;; esac
}
alive_mark() {
  alive_file_mark "$1" && return 0
  if command -v pidof >/dev/null 2>&1 && pidof "$1" >/dev/null 2>&1; then printf '🟢'; else printf '⚪'; fi
}
declare -A DASH_RSS=()
DASH_RF=5
dash_collect_rss() {
  local p list="" out="" pid tag kb
  DASH_RSS=()
  for p in "${PKGS[@]}"; do list="$list $p"; done
  if [ "$(cfg_get USE_ROOT 0)" = "1" ] && have_su; then
    out=$(su_run 'for p in'"$list"'; do pid=$(pidof "$p" | cut -d" " -f1); [ -n "$pid" ] && echo "RSS $p $(grep VmRSS /proc/$pid/status | tr -s " " | cut -d" " -f2)"; done' 2>/dev/null)
  elif command -v pidof >/dev/null 2>&1; then
    for p in "${PKGS[@]}"; do
      pid=$(pidof "$p" 2>/dev/null | cut -d' ' -f1)
      if [ -n "$pid" ] && [ -r "/proc/$pid/status" ]; then
        out+="RSS $p $(grep VmRSS "/proc/$pid/status" | tr -s ' ' | cut -d' ' -f2)"$'\n'
      fi
    done
  fi
  while read -r tag p kb; do
    [ "$tag" = "RSS" ] && [[ "$kb" =~ ^[0-9]+$ ]] && DASH_RSS[$p]=$kb
  done <<<"$out"
}
dash_frame() {
  local i=0 pkg mark up rj hr nm kb ram mt ma load n_en=0 n_ok=0 n_bad=0 sumkb=0 sumrj=0 sumrb=0 ev ts ep pk why w sep st d dv dm
  w=$(tput cols 2>/dev/null); [[ "$w" =~ ^[0-9]+$ ]] || w="${COLUMNS:-60}"
  [ "$w" -gt 60 ] && w=60; [ "$w" -lt 30 ] && w=30
  sep=$(hline ─ $((w - 2)))
  mt=$(awk '/^MemTotal/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null)
  ma=$(awk '/^MemAvailable/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null)
  load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)
  printf '%s PROCYSIS • แดชบอร์ดสด%s  %s\n' "$BOLD$C" "$N" "$(date '+%T')"
  printf ' 🧠 ว่าง %s/%s MB  ⚙️ %s  🔄 %s วิ\n' "${ma:-?}" "${mt:-?}" "${load:-?}" "$DASH_RF"
  printf '%s %s%s\n' "$C" "$sep" "$N"
  for pkg in "${PKGS[@]}"; do
    i=$((i + 1))
    if [ "$(screen_enabled "$pkg")" != "1" ]; then
      printf ' %2s ⚫ %s %s(ปิดใช้งาน)%s\n' "$i" "$(tail_str "$pkg" 22)" "$DIM" "$N"
      continue
    fi
    n_en=$((n_en + 1))
    mark=$(alive_file_mark "$pkg")
    if [ -z "$mark" ]; then
      if proc_has "$pkg"; then mark="🟢"
      elif [ "$PROC_BLIND" -eq 1 ]; then mark="❔"
      else mark="🔴"; fi
    fi
    case "$mark" in "🟢") n_ok=$((n_ok + 1)); up=$(pkg_uptime "$pkg") ;; "🔴") n_bad=$((n_bad + 1)); up="-" ;; *) up="-" ;; esac
    nm=$(cfg_get "uname.$pkg" "-")
    st=$(stat_get "$pkg" acct_state unknown)
    case "$st" in banned) st=" 🚫" ;; expired) st=" 🔑✗" ;; *) st="" ;; esac
    rj=$(stat_get "$pkg" rejoins 0); hr=$(rejoin_count_hr "$pkg"); sumrj=$((sumrj + rj))
    kb="${DASH_RSS[$pkg]:-}"
    if [ -n "$kb" ]; then ram="$(awk -v k="$kb" 'BEGIN{printf "%d", k/1024}')MB"; sumkb=$((sumkb + kb)); else ram="-"; fi
    printf ' %2s %s %s  👤%s%s\n' "$i" "$mark" "$(tail_str "$pkg" 22)" "$(tail_str "$nm" 14)" "$st"
    printf '    ⏱ %s  🔁 %s(%s)  🧠 %s\n' "$up" "$rj" "$hr" "$ram"
    if has_robux "$pkg"; then
      d=$(robux_delta "$pkg")
      if [ -n "$d" ]; then dv=${d%|*}; dm=${d#*|}; printf '    💰 R$ %s  %+d/%sน\n' "$(fmt_num "$(stat_get "$pkg" robux 0)")" "$dv" "$dm"
      else printf '    💰 R$ %s\n' "$(fmt_num "$(stat_get "$pkg" robux 0)")"; fi
      sumrb=$((sumrb + $(stat_get "$pkg" robux 0)))
    fi
  done
  printf '%s %s%s\n' "$C" "$sep" "$N"
  printf ' ใช้งาน %s | 🟢 %s | 🔴 %s | รีจอย %s\n' "$n_en" "$n_ok" "$n_bad" "$sumrj"
  [ "$sumkb" -gt 0 ] && printf ' 🧠 แอปรวม %s MB\n' "$((sumkb / 1024))"
  [ "$sumrb" -gt 0 ] && printf ' 💰 Robux รวม R$ %s\n' "$(fmt_num "$sumrb")"
  if [ -s "$REJOIN_LOG" ]; then
    printf '\n%s รีจอยล่าสุด%s\n' "$DIM" "$N"
    while IFS='|' read -r ep pk why; do
      ts=$(date -d "@$ep" +%H:%M 2>/dev/null || echo '--:--')
      printf '  %s %s %s\n' "$ts" "$(tail_str "$pk" 14)" "$why"
    done < <(tail -n 3 "$REJOIN_LOG")
  fi
  printf '\n%s [q] ออก  [+] ถี่ขึ้น  [-] ช้าลง  🟢อยู่ 🔴ไม่พบ ⏳เพิ่งเปิด ❔ไม่ทราบ%s\n' "$DIM" "$N"
}
menu_dashboard() {
  local key frame
  mapfile -t PKGS < <(detect_pkgs)
  if [ -z "${PKGS[0]:-}" ]; then printf '%s✗ ไม่พบแพ็กเกจ%s\n' "$R" "$N"; pause; return; fi
  DASH_RF=$(cfg_get DASH_REFRESH 5)
  case "$DASH_RF" in ''|*[!0-9]*) DASH_RF=5 ;; esac
  [ "$DASH_RF" -lt 2 ] && DASH_RF=2
  STOP=0; trap 'STOP=1' INT
  tput civis 2>/dev/null; clear
  while [ "$STOP" -eq 0 ]; do
    snapshot_procs
    dash_collect_rss
    frame=$(dash_frame)
    frame="${frame//$'\n'/$'\033[K\n'}"
    printf '\033[H%s\033[K\033[J' "$frame"
    key=""
    read -rsn1 -t "$DASH_RF" key
    case "$key" in
      q|Q) break ;;
      +) [ "$DASH_RF" -gt 2 ] && DASH_RF=$((DASH_RF - 1)) ;;
      -) DASH_RF=$((DASH_RF + 1)) ;;
    esac
  done
  cfg_set DASH_REFRESH "$DASH_RF"
  tput cnorm 2>/dev/null; stty sane 2>/dev/null
  trap on_int INT
  printf '\n'
}
PROFILES_DIR="$BASE/profiles"
mkdir -p "$PROFILES_DIR"
PROFILE_KEYS=(PLACE_ID VIP_LINK PKG_FILTER LAUNCH_DELAY AUTO_CLEAR LAUNCH_MODE GRID_COLS DISPLAY_SIZE ROTATE_MODE
              RJ_INTERVAL RJ_THRESHOLD RJ_EVERY RJ_GRACE RJ_STRICT REJOIN_CAP ALIVE_METHOD RJ_REPORT
              COOKIE_AUTOLOGIN AUTOEXEC_ON PERF_MODE PERF_QUALITY PERF_FPS PERF_MUTE PERF_NO3D PERF_CLEAR PERF_CLEAR_DELAY ACCT_EVERY ACCT_ALERT)
PROFILE_GLOBS=('place.*' 'vip.*' 'enabled.*' 'aeoff.*' 'aeto.*')
PROF_NAMES=()
profile_clean_name() { printf '%s' "$1" | tr -d '/\\' | sed 's/^[ .]*//; s/[ ]*$//; s/  */_/g'; }
profile_list() {
  local d; PROF_NAMES=()
  for d in "$PROFILES_DIR"/*/; do [ -d "$d" ] && PROF_NAMES+=("$(basename "$d")"); done
}
profile_save() {
  local name="$1" d k g f
  [ -n "$name" ] || return 1
  d="$PROFILES_DIR/$name"
  rm -rf "$d"; mkdir -p "$d/cfg" "$d/uri" || return 1
  for k in "${PROFILE_KEYS[@]}"; do [ -f "$CFG/$k" ] && cp -f "$CFG/$k" "$d/cfg/"; done
  for g in "${PROFILE_GLOBS[@]}"; do
    for f in "$CFG"/$g; do [ -f "$f" ] && cp -f "$f" "$d/cfg/"; done
  done
  for f in "$STATE"/uri.*; do [ -f "$f" ] && cp -f "$f" "$d/uri/"; done
  date '+%F %T' > "$d/saved_at"
  log INFO "บันทึกโปรไฟล์ $name"
}
profile_load() {
  local name="$1" d="$PROFILES_DIR/$1" k g f
  [ -d "$d" ] || return 1
  [ "$name" = "_ก่อนโหลดล่าสุด" ] || profile_save "_ก่อนโหลดล่าสุด" >/dev/null 2>&1
  for k in "${PROFILE_KEYS[@]}"; do rm -f "$CFG/$k"; done
  for g in "${PROFILE_GLOBS[@]}"; do
    for f in "$CFG"/$g; do [ -f "$f" ] && rm -f "$f"; done
  done
  cp -f "$d/cfg/"* "$CFG/" 2>/dev/null
  rm -f "$STATE"/uri.*
  cp -f "$d/uri/"* "$STATE/" 2>/dev/null
  log INFO "โหลดโปรไฟล์ $name"
  return 0
}
profile_show_list() {
  local i=0 n d at nu
  profile_list
  printf '\n%sโปรไฟล์ที่บันทึกไว้%s\n' "$C" "$N"
  if [ "${#PROF_NAMES[@]}" -eq 0 ]; then printf '  %s— ยังไม่มี (บันทึกที่ข้อ 1)%s\n' "$DIM" "$N"; return; fi
  for n in "${PROF_NAMES[@]}"; do
    i=$((i + 1)); d="$PROFILES_DIR/$n"
    at=$(cat "$d/saved_at" 2>/dev/null)
    nu=$(find "$d/uri" -type f 2>/dev/null | wc -l)
    printf '  %s) %s  %s[%s | ลิงก์เกม %s จอ]%s\n' "$i" "$n" "$DIM" "${at:--}" "$nu" "$N"
  done
}
PROF_PICK=""
profile_pick() {
  local in="$1" i
  PROF_PICK=""
  profile_list
  if [[ "$in" =~ ^[0-9]+$ ]] && [ "$((10#$in))" -ge 1 ] && [ "$((10#$in))" -le "${#PROF_NAMES[@]}" ]; then
    PROF_PICK="${PROF_NAMES[$((10#$in - 1))]}"; return 0
  fi
  for i in "${PROF_NAMES[@]}"; do [ "$i" = "$in" ] && { PROF_PICK="$i"; return 0; }; done
  return 1
}
profile_detail() {
  local d="$PROFILES_DIR/$1" f k v
  printf '\n%sโปรไฟล์ %s%s (%s)\n' "$Y" "$1" "$N" "$(cat "$d/saved_at" 2>/dev/null)"
  for k in PLACE_ID VIP_LINK LAUNCH_DELAY AUTO_CLEAR RJ_INTERVAL RJ_THRESHOLD RJ_EVERY REJOIN_CAP ALIVE_METHOD RJ_REPORT AUTOEXEC_ON; do
    [ -s "$d/cfg/$k" ] && printf '  %-16s = %s\n' "$k" "$(head -c 70 "$d/cfg/$k")"
  done
  for f in "$d"/cfg/enabled.* "$d"/cfg/aeto.* "$d"/cfg/aeoff.*; do
    [ -f "$f" ] && printf '  %-16s = %s\n' "$(basename "$f")" "$(head -c 70 "$f")"
  done
  for f in "$d"/uri/uri.*; do
    [ -f "$f" ] && printf '  ลิงก์ %s\n    %s\n' "$(basename "$f" | sed 's/^uri\.//')" "$(head -c 90 "$f")"
  done
}
profile_launch() {
  local name="$1" p u miss=0
  profile_load "$name" || { printf '%s✗ โหลดไม่สำเร็จ%s\n' "$R" "$N"; return 1; }
  mapfile -t PKGS < <(detect_pkgs)
  if [ -z "${PKGS[0]:-}" ]; then printf '%s✗ ไม่พบแพ็กเกจ%s\n' "$R" "$N"; return 1; fi
  URIS=()
  for p in "${PKGS[@]}"; do
    u=$(saved_uri "$p"); URIS+=("$u"); [ -z "$u" ] && miss=$((miss + 1))
  done
  if [ "$miss" -gt 0 ]; then
    printf '%s⚠ มี %s จอที่โปรไฟล์นี้ไม่มีลิงก์เกม (จะเปิดแอปเฉยๆ)%s\n' "$Y" "$miss" "$N"
    confirm "ดำเนินการต่อ?" || return 1
  fi
  run_batch "โปรไฟล์ $name"
  [ "$2" = "watch" ] && watchdog_run
  return 0
}
menu_profiles() {
  local c n name
  while true; do
    banner
    printf '%sโปรไฟล์ (บันทึก/สลับชุดตั้งค่า)%s\n' "$Y" "$N"
    profile_show_list
    printf '\n 1) บันทึกการตั้งค่าตอนนี้เป็นโปรไฟล์\n'
    printf ' 2) โหลดโปรไฟล์ (ตั้งค่าอย่างเดียว ยังไม่เปิดเกม)\n'
    printf ' 3) โหลดโปรไฟล์ แล้วเปิดทุกจอทันที\n'
    printf ' 4) โหลดโปรไฟล์ เปิดทุกจอ แล้วเริ่มเฝ้าจอต่อ\n'
    printf ' 5) ดูรายละเอียดโปรไฟล์\n'
    printf ' 6) ลบโปรไฟล์\n'
    printf ' 0) กลับ\n\n'
    printf '%sไม่เก็บคุกกี้/Webhook/สิทธิ์รูท | โหลดแล้วย้อนกลับได้ที่โปรไฟล์ "_ก่อนโหลดล่าสุด"%s\n\n' "$DIM" "$N"
    read -rp "เลือก: " c || on_exit
    case "$c" in
      1) ask "ชื่อโปรไฟล์" ""
         name=$(profile_clean_name "$REPLY_VAL")
         if [ -z "$name" ]; then printf '%s✗ ชื่อไม่ถูกต้อง%s\n' "$R" "$N"; pause; continue; fi
         if [ -d "$PROFILES_DIR/$name" ]; then confirm "มีโปรไฟล์ชื่อนี้อยู่แล้ว เขียนทับ?" || continue; fi
         if profile_save "$name"; then printf '%s✓ บันทึกโปรไฟล์ "%s" แล้ว%s\n' "$G" "$name" "$N"
         else printf '%s✗ บันทึกไม่สำเร็จ%s\n' "$R" "$N"; fi
         pause ;;
      2|3|4|5|6)
         read -rp 'เลขหรือชื่อโปรไฟล์: ' n || continue
         if ! profile_pick "$n"; then printf '%s✗ ไม่พบโปรไฟล์%s\n' "$R" "$N"; pause; continue; fi
         case "$c" in
           2) profile_load "$PROF_PICK" && printf '%s✓ โหลด "%s" แล้ว%s\n' "$G" "$PROF_PICK" "$N"; pause ;;
           3) banner; profile_launch "$PROF_PICK"; pause ;;
           4) banner; profile_launch "$PROF_PICK" watch ;;
           5) profile_detail "$PROF_PICK"; pause ;;
           6) if confirm "ลบโปรไฟล์ \"$PROF_PICK\"?"; then rm -rf "$PROFILES_DIR/$PROF_PICK"; echo "ลบแล้ว"; log INFO "ลบโปรไฟล์ $PROF_PICK"; fi; pause ;;
         esac ;;
      0) return ;;
    esac
  done
}
PERF_DATA_ROOT="${PERF_DATA_ROOT:-/data/data}"
PERF_DIR="$STATE/perf"
PERF_FILE=""; PERF_MSG=""; PERF_ERR=""
PERF_APPLIED=(); PERF_MISSING=()
mkdir -p "$PERF_DIR"
perf_root_ok() { [ "$(cfg_get USE_ROOT 0)" = "1" ] && have_su; }
perf_find() {
  local pkg="$1" f out
  PERF_FILE=""
  f="$PERF_DATA_ROOT/$pkg/files/appData/GlobalBasicSettings_13.xml"
  out=$(su_run "if [ -f '$f' ]; then echo '$f'; else find '$PERF_DATA_ROOT/$pkg' -maxdepth 6 -type f -name 'GlobalBasicSettings*.xml' 2>/dev/null | head -n 1; fi")
  out="${out%%$'\n'*}"
  [ -n "$out" ] && ae_path_ok "$out" && { PERF_FILE="$out"; return 0; }
  return 1
}
perf_val_in() {
  local v
  grep -q "name=\"$2\"" "$1" 2>/dev/null || return 1
  v=$(grep -o "name=\"$2\"[^>]*>[^<]*" "$1" | head -n 1 | sed 's/^[^>]*>//')
  printf '%s' "$v"
}
perf_edit() {
  local pkg="$1"; shift
  local pair k v tmpd tmp tuid cur ok=0 orig="$PERF_DIR/$pkg.orig" out rb
  PERF_APPLIED=(); PERF_MISSING=(); PERF_ERR=""; PERF_MSG=""
  perf_root_ok || { PERF_ERR="ต้องเปิดใช้รูท (ตั้งค่า ข้อ 4)"; return 1; }
  perf_find "$pkg" || { PERF_ERR="ไม่พบไฟล์ GlobalBasicSettings (เปิด Roblox ของจอนี้ค้างไว้สักครั้งก่อน)"; return 1; }
  tuid=$(id -u)
  tmpd=$(umask 077; mktemp -d "$STATE/perfwork.XXXXXX") || { PERF_ERR="สร้างโฟลเดอร์ชั่วคราวไม่ได้"; return 1; }
  chmod 700 "$tmpd"; tmp="$tmpd/s.xml"
  su_run "cp '$PERF_FILE' '$tmp' && chown $tuid:$tuid '$tmp' && chmod 600 '$tmp'" >/dev/null 2>&1
  if [ ! -s "$tmp" ]; then PERF_ERR="คัดลอกไฟล์ตั้งค่าไม่สำเร็จ"; ck_wipe "$tmpd"; return 1; fi
  if [ ! -s "$orig" ]; then
    for pair in "$@"; do
      k="${pair%%=*}"
      cur=$(perf_val_in "$tmp" "$k") && printf '%s=%s\n' "$k" "$cur" >> "$orig"
    done
  fi
  for pair in "$@"; do
    k="${pair%%=*}"; v="${pair#*=}"
    [[ "$k" =~ ^[A-Za-z0-9_]+$ ]] && [[ "$v" =~ ^[A-Za-z0-9._-]+$ ]] || { PERF_MISSING+=("$k"); continue; }
    if grep -q "name=\"$k\"" "$tmp"; then
      sed -i -E "s#(name=\"$k\"[^>]*>)[^<]*(<)#\\1$v\\2#" "$tmp"
      PERF_APPLIED+=("$k=$v")
    else
      PERF_MISSING+=("$k")
    fi
  done
  if [ "${#PERF_APPLIED[@]}" -eq 0 ]; then PERF_ERR="ไม่พบคีย์ที่ต้องแก้ในไฟล์เลย (ดูโครงไฟล์จริงที่ข้อ 6)"; ck_wipe "$tmpd"; return 1; fi
  su_run "cat '$tmp' > '$PERF_FILE'" >/dev/null 2>&1
  su_run "cp '$PERF_FILE' '$tmp.chk' && chown $tuid:$tuid '$tmp.chk' && chmod 600 '$tmp.chk'" >/dev/null 2>&1
  for pair in "${PERF_APPLIED[@]}"; do
    k="${pair%%=*}"; v="${pair#*=}"
    rb=$(perf_val_in "$tmp.chk" "$k")
    [ "$rb" = "$v" ] && ok=$((ok + 1)) || PERF_ERR="$PERF_ERR ตรวจซ้ำไม่ตรง $k (ได้ '$rb')"
  done
  ck_wipe "$tmpd"
  if [ "$ok" -ne "${#PERF_APPLIED[@]}" ]; then PERF_ERR="เขียนไฟล์แล้วแต่ตรวจซ้ำไม่ผ่านครบ:$PERF_ERR"; return 1; fi
  PERF_MSG="ตั้ง ${PERF_APPLIED[*]}"
  [ "${#PERF_MISSING[@]}" -gt 0 ] && PERF_MSG="$PERF_MSG | ไม่พบคีย์: ${PERF_MISSING[*]}"
  log INFO "$pkg perf: $PERF_MSG"
  return 0
}
perf_apply_cfg() {
  local pkg="$1" q fps
  local -a pairs=()
  q=$(cfg_get PERF_QUALITY 1); case "$q" in ''|*[!0-9]*) q=1 ;; esac
  fps=$(cfg_get PERF_FPS 0);   case "$fps" in ''|*[!0-9]*) fps=0 ;; esac
  pairs+=("SavedQualityLevel=$q" "GraphicsQualityLevel=$q")
  [ "$fps" -gt 0 ] && pairs+=("FramerateCap=$fps")
  [ "$(cfg_get PERF_MUTE 1)" = "1" ] && pairs+=("MasterVolume=0")
  perf_edit "$pkg" "${pairs[@]}"
}
perf_restore() {
  local pkg="$1" orig="$PERF_DIR/$1.orig" line
  local -a pairs=()
  [ -s "$orig" ] || { PERF_ERR="ไม่มีค่าเดิมที่เก็บไว้ (ยังไม่เคยแก้จอนี้)"; return 1; }
  while IFS= read -r line; do [ -n "$line" ] && pairs+=("$line"); done < "$orig"
  mv -f "$orig" "$orig.restoring"
  if perf_edit "$pkg" "${pairs[@]}"; then rm -f "$orig" "$orig.restoring"; return 0; fi
  mv -f "$orig.restoring" "$orig"; rm -f "$orig.restoring"
  return 1
}
perf_inspect() {
  local p i=0 f out
  banner; load_pkgs || return
  if ! perf_root_ok; then printf '\n%s✗ ต้องเปิดใช้รูท (ตั้งค่า ข้อ 4) ถึงอ่านไฟล์ของแอปได้%s\n' "$R" "$N"; pause; return; fi
  for p in "${PKGS[@]}"; do
    i=$((i + 1))
    printf '\n%s%s) %s%s\n' "$Y" "$i" "$p" "$N"
    if ! perf_find "$p"; then printf '   %s✗ ไม่พบไฟล์ตั้งค่า (เปิด Roblox ของจอนี้ค้างไว้สักครั้ง)%s\n' "$R" "$N"; continue; fi
    printf '   ไฟล์: %s\n' "$PERF_FILE"
    out=$(su_run "grep -iE 'name=\"[^\"]*(Quality|Framerate|FPS|Volume)[^\"]*\"' '$PERF_FILE' | head -n 12")
    if [ -n "$out" ]; then printf '%s\n' "$out" | sed 's/^[[:space:]]*/     /'; else printf '   %s(ไม่พบบรรทัดเกี่ยวกับ Quality/Framerate/Volume)%s\n' "$DIM" "$N"; fi
    [ -s "$PERF_DIR/$p.orig" ] && printf '   %sมีค่าเดิมเก็บไว้ (กู้คืนได้ที่ข้อ 7)%s\n' "$G" "$N"
  done
  printf '\n%sถ้ามีคีย์ที่อยากให้แก้เพิ่ม ส่งข้อความตรงนี้มาให้ผมดูได้ครับ%s\n' "$DIM" "$N"
  pause
}
perf_apply_all() {
  local p
  banner; load_pkgs || return
  printf '\n%sจะปิดแอป (Force Stop) ของทุกจอที่เปิดใช้งานก่อนแก้ไฟล์ และต้องเปิดเกมใหม่เองหลังจากนั้น%s\n' "$Y" "$N"
  confirm "ดำเนินการต่อ?" || return
  for p in "${PKGS[@]}"; do
    [ "$(screen_enabled "$p")" = "1" ] || continue
    printf '\n%s%s%s\n' "$C" "$p" "$N"
    force_stop "$p"; sleep 1
    if perf_apply_cfg "$p"; then printf '  %s✓ %s%s\n' "$G" "$PERF_MSG" "$N"
    else printf '  %s✗ %s%s\n' "$R" "$PERF_ERR" "$N"; fi
  done
  pause
}
perf_restore_all() {
  local p
  banner; load_pkgs || return
  confirm "กู้คืนค่าเดิมทุกจอ (จะ Force Stop แอปก่อน)?" || return
  for p in "${PKGS[@]}"; do
    printf '\n%s%s%s\n' "$C" "$p" "$N"
    force_stop "$p"; sleep 1
    if perf_restore "$p"; then printf '  %s✓ กู้คืนแล้ว: %s%s\n' "$G" "$PERF_MSG" "$N"
    else printf '  %s— %s%s\n' "$Y" "$PERF_ERR" "$N"; fi
  done
  pause
}
PERF3D_NAME="perf3d.lua"
perf_gen_lua() {
  local f="$SCRIPTS_DIR/$PERF3D_NAME" no3d clr delay
  no3d=$(cfg_get PERF_NO3D 0); clr=$(cfg_get PERF_CLEAR 0)
  delay=$(cfg_get PERF_CLEAR_DELAY 20); case "$delay" in ''|*[!0-9]*) delay=20 ;; esac
  if [ "$no3d" != "1" ] && [ "$clr" != "1" ]; then
    [ -f "$f" ] && rm -f "$f"
    return 0
  fi
  mkdir -p "$SCRIPTS_DIR"
  {
    printf -- '-- PROCYSIS: สร้างอัตโนมัติจากโหมดประหยัดสเปก (แก้ที่เมนู f ไม่ต้องแก้ไฟล์นี้)\n'
    printf 'local NO3D = %s\nlocal CLEAR = %s\nlocal DELAY = %s\n' \
      "$([ "$no3d" = "1" ] && echo true || echo false)" \
      "$([ "$clr" = "1" ] && echo true || echo false)" "$delay"
    cat <<'LUA'
if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
local function inCharacter(inst)
  local m = inst:FindFirstAncestorOfClass("Model")
  while m do
    if m:FindFirstChildOfClass("Humanoid") then return true end
    m = m:FindFirstAncestorOfClass("Model")
  end
  return false
end
local KILL = {
  Decal = true, Texture = true, ParticleEmitter = true, Trail = true, Beam = true,
  Smoke = true, Fire = true, Sparkles = true, Explosion = true, Highlight = true,
  SurfaceAppearance = true, MeshPart = false,
}
local function strip(inst)
  if inst:IsA("Camera") or inst:IsA("Terrain") or inCharacter(inst) then return end
  if KILL[inst.ClassName] then
    pcall(function() inst:Destroy() end)
  elseif inst:IsA("BasePart") then
    pcall(function()
      inst.Transparency = 1
      inst.CastShadow = false
    end)
  end
end
local function clearMap()
  pcall(function() workspace.Terrain:Clear() end)
  pcall(function() workspace.StreamingEnabled = workspace.StreamingEnabled end)
  for _, e in ipairs(Lighting:GetChildren()) do
    if e:IsA("PostEffect") or e:IsA("Atmosphere") or e:IsA("Sky") or e:IsA("Clouds") then
      pcall(function() e:Destroy() end)
    end
  end
  pcall(function()
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
  end)
  local n = 0
  for _, d in ipairs(workspace:GetDescendants()) do
    strip(d)
    n = n + 1
    if n % 400 == 0 then task.wait() end
  end
  workspace.DescendantAdded:Connect(function(d)
    task.defer(strip, d)
  end)
end
if CLEAR then
  task.spawn(function()
    task.wait(DELAY)
    pcall(clearMap)
  end)
end
if NO3D then
  task.spawn(function()
    task.wait(CLEAR and (DELAY + 5) or 3)
    pcall(function() RunService:Set3dRenderingEnabled(false) end)
  end)
end
print("[PROCYSIS] perf3d ทำงานแล้ว")
LUA
  } > "$f"
}
menu_perf() {
  local c
  while true; do
    banner
    printf '%sโหมดประหยัดสเปก (ลดแลก)%s\n\n' "$Y" "$N"
    printf ' 1) เปิดใช้อัตโนมัติก่อนเปิดเกมทุกครั้ง : %s\n' "$(onoff "$(cfg_get PERF_MODE 0)")"
    printf ' 2) ระดับกราฟิก : %s (1 = ต่ำสุด)\n' "$(cfg_get PERF_QUALITY 1)"
    printf ' 3) ล็อก FPS (FramerateCap) : %s (0 = ไม่แตะ)\n' "$(cfg_get PERF_FPS 0)"
    printf ' 4) ปิดเสียงเกม : %s\n' "$(onoff "$(cfg_get PERF_MUTE 1)")"
    printf ' 5) ใช้ตอนนี้กับทุกจอ (ปิดแอปก่อน)\n'
    printf ' 6) ตรวจไฟล์ตั้งค่าจริงของแต่ละจอ (ดูว่ามีคีย์ไหนบ้าง)\n'
    printf ' 7) กู้คืนค่าเดิมทุกจอ\n'
    printf ' 8) ปิดการเรนเดอร์ 3D (จอดำ แต่เกม/สคริปต์ยังรัน ประหยัด GPU) : %s\n' "$(onoff "$(cfg_get PERF_NO3D 0)")"
    printf ' 9) ลบของในแมพ (Part/Decal/เอฟเฟกต์/Terrain ฝั่งเรา) : %s  (หน่วง %s วิ)\n' "$(onoff "$(cfg_get PERF_CLEAR 0)")" "$(cfg_get PERF_CLEAR_DELAY 20)"
    printf ' 0) กลับ\n\n'
    printf '%sข้อ 1-7 ต้องเปิดใช้รูท | ข้อ 8-9 ใช้ผ่าน Auto Execute (ต้องเปิดข้อ e-6) | ข้อ 9 อาจทำให้สคริปต์ฟาร์มที่ต้องใช้ของในแมพพัง ลองทีละจอก่อน%s\n\n' "$DIM" "$N"
    read -rp "เลือก: " c || on_exit
    case "$c" in
      1) if [ "$(cfg_get PERF_MODE 0)" = "1" ]; then cfg_set PERF_MODE 0; else cfg_set PERF_MODE 1; fi ;;
      2) set_num PERF_QUALITY "ระดับกราฟิก (1 = ต่ำสุด)" 1 1 ;;
      3) set_num PERF_FPS "ล็อก FPS เท่าไหร่ (0 = ไม่แตะ)" 0 0 ;;
      4) if [ "$(cfg_get PERF_MUTE 1)" = "1" ]; then cfg_set PERF_MUTE 0; else cfg_set PERF_MUTE 1; fi ;;
      5) perf_apply_all ;;
      6) perf_inspect ;;
      7) perf_restore_all ;;
      8) if [ "$(cfg_get PERF_NO3D 0)" = "1" ]; then cfg_set PERF_NO3D 0; else cfg_set PERF_NO3D 1; fi; perf_gen_lua; perf3d_note ;;
      9) if [ "$(cfg_get PERF_CLEAR 0)" = "1" ]; then cfg_set PERF_CLEAR 0; else
           cfg_set PERF_CLEAR 1; set_num PERF_CLEAR_DELAY "หน่วงกี่วินาทีหลังเข้าเกมก่อนลบ (ให้สคริปต์อื่นโหลดก่อน)" 20 5
         fi; perf_gen_lua; perf3d_note ;;
      0) return ;;
    esac
  done
}
perf3d_note() {
  local f="$SCRIPTS_DIR/$PERF3D_NAME"
  if [ -f "$f" ]; then
    printf '%s✓ สร้าง %s แล้ว (วางให้อัตโนมัติตอนเข้าเกม/ซิงก์ที่ e-4 | กำหนดจอได้ที่ e-9)%s\n' "$G" "$PERF3D_NAME" "$N"
  else
    printf '%s✓ ปิดทั้งสองข้อแล้ว ลบ %s ออกจากรายการสคริปต์ (ซิงก์เพื่อเอาออกจากโฟลเดอร์ Delta)%s\n' "$G" "$PERF3D_NAME" "$N"
  fi
  sleep 2
}
ACCT_LOG="$STATE/robux.log"
ACCT_STATE=""; ACCT_ROBUX=""
fmt_num() { awk -v n="${1:-0}" 'BEGIN{s=sprintf("%d",n); o=""; while(length(s)>3){o="," substr(s,length(s)-2) o; s=substr(s,1,length(s)-3)} print s o}'; }
acct_get() {
  local h out
  ACCT_HTTP=""; ACCT_BODY=""
  h=$(ck_hdr "$1") || return 1
  out=$(curl -s -m 15 -A "$JOIN_UA" -H @"$h" -w $'\n%{http_code}' "$2" 2>/dev/null)
  rm -f "$h"
  ACCT_HTTP="${out##*$'\n'}"; ACCT_BODY="${out%$'\n'*}"
  [ -n "$ACCT_HTTP" ] && [ "$ACCT_HTTP" != "000" ]
}
acct_finish() {
  local pkg="$1" prev now nm
  now=$(date +%s)
  prev=$(stat_get "$pkg" acct_state unknown)
  nm=$(cfg_get "uname.$pkg" "$pkg")
  case "$ACCT_STATE" in
    ok|expired|banned)
      stat_set "$pkg" acct_state "$ACCT_STATE"; stat_set "$pkg" acct_ts "$now"
      if [ "$ACCT_STATE" != "$prev" ] && [ "$prev" != "unknown" ] || { [ "$prev" = "unknown" ] && [ "$ACCT_STATE" != "ok" ]; }; then
        if [ "$(cfg_get ACCT_ALERT 1)" = "1" ]; then
          case "$ACCT_STATE" in
            banned)  log ERROR "$pkg บัญชีถูกแบน"; notify_rejoin "🚫 $nm" "บัญชีถูกแบน (จอ $pkg) ตรวจพบจาก isBanned" 15158332 ;;
            expired) log ERROR "$pkg คุกกี้หมดอายุ/ออกจากระบบ"
                     [ "${W_BADCK[$pkg]:-0}" = "1" ] || notify_rejoin "🔑 $nm" "คุกกี้หมดอายุหรือบัญชีออกจากระบบ (จอ $pkg) ต้องใส่คุกกี้ใหม่" 15158332 ;;
            ok)      log INFO "$pkg บัญชีกลับมาปกติ"; notify_rejoin "✅ $nm" "บัญชีกลับมาปกติ (จอ $pkg)" 3066993 ;;
          esac
        fi
      fi
      [ "$ACCT_STATE" = "expired" ] && W_BADCK[$pkg]=1
      [ "$ACCT_STATE" = "ok" ] && W_BADCK[$pkg]=0 ;;
  esac
  if [ "$ACCT_STATE" = "ok" ] && [ -n "$ACCT_ROBUX" ]; then
    printf '%s|%s|%s\n' "$now" "$pkg" "$ACCT_ROBUX" >> "$ACCT_LOG"
    stat_set "$pkg" robux "$ACCT_ROBUX"; stat_set "$pkg" robux_ts "$now"
    [ -s "$STATS/$pkg.robux_base" ] || stat_set "$pkg" robux_base "$ACCT_ROBUX"
    if [ "$(wc -l < "$ACCT_LOG" 2>/dev/null || echo 0)" -gt 2000 ]; then
      tail -n 1000 "$ACCT_LOG" > "$ACCT_LOG.tmp" && mv -f "$ACCT_LOG.tmp" "$ACCT_LOG"
    fi
  fi
}
acct_check() {
  local pkg="$1" ck uid rc banned
  ACCT_STATE="error"; ACCT_ROBUX=""
  ck=$(pkg_cookie "$pkg"); [ -n "$ck" ] || { ACCT_STATE="nocookie"; return 2; }
  uid=$(cfg_get "uid.$pkg")
  if [ -z "$uid" ]; then
    cookie_check "$ck"; rc=$?
    if [ "$rc" -eq 0 ]; then
      uid="$CK_UID"; cfg_set "uid.$pkg" "$uid"; [ -n "$CK_NAME" ] && cfg_set "uname.$pkg" "$CK_NAME"
    else
      [ "$rc" -eq 1 ] && ACCT_STATE="expired"
      acct_finish "$pkg"; return 0
    fi
  fi
  if acct_get "$ck" "https://economy.roblox.com/v1/users/$uid/currency"; then
    case "$ACCT_HTTP" in
      200) ACCT_ROBUX=$(grep -oE '"robux":[0-9]+' <<<"$ACCT_BODY" | head -n 1 | cut -d: -f2)
           [ -n "$ACCT_ROBUX" ] && ACCT_STATE="ok" ;;
      401) ACCT_STATE="expired" ;;
      429) ACCT_STATE="busy" ;;
      *)   log WARN "$pkg economy HTTP=$ACCT_HTTP" ;;
    esac
  fi
  banned=$(curl -s -m 15 -A "$JOIN_UA" "https://users.roblox.com/v1/users/$uid" 2>/dev/null | grep -oE '"isBanned": ?(true|false)' | head -n 1 | grep -oE 'true|false')
  [ "$banned" = "true" ] && ACCT_STATE="banned"
  acct_finish "$pkg"
  return 0
}
acct_check_all() {
  local p n=0 st
  for p in "${PKGS[@]}"; do
    [ "$(screen_enabled "$p")" = "1" ] || continue
    [ -s "$CFG/cookie.$p" ] || continue
    n=$((n + 1))
    acct_check "$p"
    if [ "$1" != "quiet" ]; then
      printf ' %s : ' "$p"
      case "$ACCT_STATE" in
        ok)      printf '%s✓ ปกติ%s  💰 R$ %s\n' "$G" "$N" "$(fmt_num "$ACCT_ROBUX")" ;;
        expired) printf '%s✗ คุกกี้หมดอายุ/ออกจากระบบ%s\n' "$R" "$N" ;;
        banned)  printf '%s🚫 บัญชีถูกแบน%s\n' "$R" "$N" ;;
        busy)    printf '%s⏳ ถูกจำกัดความถี่ รอสักครู่แล้วลองใหม่%s\n' "$Y" "$N" ;;
        *)       printf '%s? ตรวจไม่ได้ (เน็ต/ระบบ Roblox)%s\n' "$Y" "$N" ;;
      esac
    fi
    sleep 1
  done
  [ "$n" -eq 0 ] && [ "$1" != "quiet" ] && printf '%s— ยังไม่มีจอที่ใส่คุกกี้ (เมนู c ข้อ 1)%s\n' "$Y" "$N"
  return 0
}
robux_delta() {
  awk -F'|' -v p="$1" -v now="$(date +%s)" '
    $2==p && now-$1<=3600 { if (!f) { f=$1; fv=$3 } l=$1; lv=$3 }
    END { if (f && l>f) printf "%d|%d", lv-fv, int((l-f)/60) }' "$ACCT_LOG" 2>/dev/null
}
acct_summary() {
  local pkg="$1" rb base d dv dm tot st
  has_robux "$pkg" || return 1
  rb=$(stat_get "$pkg" robux 0)
  base=$(stat_get "$pkg" robux_base "$rb")
  d=$(robux_delta "$pkg"); tot=$((rb - base))
  printf '💰 R$ %s' "$(fmt_num "$rb")"
  if [ -n "$d" ]; then dv=${d%|*}; dm=${d#*|}; printf ' | %+d ใน %s นาที' "$dv" "$dm"; else printf ' | รอข้อมูลรอบถัดไป'; fi
  printf ' | รวมตั้งแต่เริ่ม %+d' "$tot"
}
has_robux() { [ -s "$STATS/$1.robux" ]; }
acct_state_text() {
  case "$1" in
    ok) printf '✅ ปกติ' ;; expired) printf '🔑 คุกกี้หมดอายุ' ;; banned) printf '🚫 ถูกแบน' ;;
    busy) printf '⏳ ถูกจำกัดความถี่' ;; error) printf '❔ ตรวจไม่ได้' ;; *) printf '➖ ยังไม่เคยตรวจ' ;;
  esac
}
menu_accounts() {
  local c p i st ts age
  while true; do
    banner
    mapfile -t PKGS < <(detect_pkgs)
    printf '%sบัญชี / Robux%s %s(ใช้คุกกี้ของแต่ละจอ ต้องใส่คุกกี้ที่เมนู c ก่อน)%s\n' "$Y" "$N" "$DIM" "$N"
    i=0
    for p in "${PKGS[@]}"; do
      i=$((i + 1))
      printf '\n %s) %s  👤 %s\n' "$i" "$p" "$(cfg_get "uname.$p" "-")"
      if [ ! -s "$CFG/cookie.$p" ]; then printf '    %s— ยังไม่มีคุกกี้%s\n' "$DIM" "$N"; continue; fi
      st=$(stat_get "$p" acct_state unknown); ts=$(stat_get "$p" acct_ts 0)
      age=""; [ "$ts" -gt 0 ] && age=" (ตรวจเมื่อ $(fmt_dur $(( $(date +%s) - ts ))) ที่แล้ว)"
      printf '    สถานะ: %s%s\n' "$(acct_state_text "$st")" "$age"
      acct_summary "$p" >/dev/null && printf '    %s\n' "$(acct_summary "$p")"
    done
    printf '\n 1) ตรวจตอนนี้ทุกจอ\n'
    printf ' 2) ตรวจอัตโนมัติระหว่างเฝ้าจอ : ทุก %s นาที (0=ปิด)\n' "$(cfg_get ACCT_EVERY 10)"
    printf ' 3) แจ้งเตือนเมื่อบัญชีมีปัญหา : %s\n' "$(onoff "$(cfg_get ACCT_ALERT 1)")"
    printf ' 4) ตั้งฐานนับใหม่ (เริ่มนับ "รวมตั้งแต่เริ่ม" ใหม่จากยอดตอนนี้)\n'
    printf ' 5) ล้างประวัติ Robux\n'
    printf ' 0) กลับ\n\n'
    printf '%sยอดคือยอดคงเหลือ ถ้ามีการซื้อ/ใช้จ่ายส่วนต่างจะติดลบ | แบนตรวจจากสถานะสาธารณะ (isBanned) อาจไม่เห็นการแบนชั่วคราวบางแบบ%s\n\n' "$DIM" "$N"
    read -rp "เลือก: " c || on_exit
    case "$c" in
      1) echo; acct_check_all; pause ;;
      2) set_num ACCT_EVERY "ตรวจทุกกี่นาที (0=ปิด)" 10 0 ;;
      3) if [ "$(cfg_get ACCT_ALERT 1)" = "1" ]; then cfg_set ACCT_ALERT 0; else cfg_set ACCT_ALERT 1; fi ;;
      4) for p in "${PKGS[@]}"; do has_robux "$p" && stat_set "$p" robux_base "$(stat_get "$p" robux 0)"; done; echo "ตั้งฐานใหม่แล้ว"; sleep 1 ;;
      5) if confirm "ล้างประวัติ Robux ทุกจอ?"; then rm -f "$ACCT_LOG" "$STATS"/*.robux "$STATS"/*.robux_ts "$STATS"/*.robux_base; echo "ล้างแล้ว"; sleep 1; fi ;;
      0) return ;;
    esac
  done
}
on_exit() {
  rootsh_stop
  printf '\n%sขอบคุณที่ใช้ PROCYSIS%s\n' "$C" "$N"
  log INFO "===== ปิดโปรแกรม ====="
  termux-wake-unlock 2>/dev/null
  exit 0
}
on_int() {
  rootsh_stop
  echo
  log INFO "ถูกขัดจังหวะ (Ctrl+C)"
  termux-wake-unlock 2>/dev/null
  exit 130
}

# ==================== PROCYSIS AUTO INSTALLER (GitHub) ====================
INSTALL_DIR="$BASE/installer"
mkdir -p "$INSTALL_DIR"

declare -A APK_URLS=(
  ["PROCYSIS DELTA 01.apk"]="https://github.com/procysis/Procysis-APKS/releases/download/v1.0/PROCYSIS.DELTA.01.apk"
  ["PROCYSIS DELTA 02.apk"]="https://github.com/procysis/Procysis-APKS/releases/download/v1.0/PROCYSIS.DELTA.02.apk"
  ["PROCYSIS DELTA 03.apk"]="https://github.com/procysis/Procysis-APKS/releases/download/v1.0/PROCYSIS.DELTA.03.apk"
  ["PROCYSIS DELTA 04.apk"]="https://github.com/procysis/Procysis-APKS/releases/download/v1.0/PROCYSIS.DELTA.04.apk"
  ["PROCYSIS DELTA 05.apk"]="https://github.com/procysis/Procysis-APKS/releases/download/v1.0/PROCYSIS.DELTA.05.apk"
  ["PROCYSIS DELTA 06.apk"]="https://github.com/procysis/Procysis-APKS/releases/download/v1.0/PROCYSIS.DELTA.06.apk"
  ["PROCYSIS DELTA 07.apk"]="https://github.com/procysis/Procysis-APKS/releases/download/v1.0/PROCYSIS.DELTA.07.apk"
  ["PROCYSIS DELTA 08.apk"]="https://github.com/procysis/Procysis-APKS/releases/download/v1.0/PROCYSIS.DELTA.08.apk"
)

download_apk() {
  local name="$1" dest="$2"
  local url="${APK_URLS[$name]}"
  printf '   ⬇️  กำลังดาวน์โหลด %s ...\n' "$name"
  if curl -L -f -o "$dest" --retry 3 --retry-delay 2 -A "$JOIN_UA" "$url"; then
    printf '   %s✓ ดาวน์โหลดสำเร็จ%s\n' "$G" "$N"
    return 0
  else
    printf '   %s✗ ดาวน์โหลดล้มเหลว%s\n' "$R" "$N"
    return 1
  fi
}

install_apk() {
  local apk="$1" name="$2" out rc sid
  printf '   📦 กำลังติดตั้ง %s ...\n' "$name"

  # วิธี 1: pm ปกติ
  out=$(pm install -r -t -g "$apk" 2>&1); rc=$?
  if printf '%s' "$out" | grep -qiE 'success|Success' || [ $rc -eq 0 ]; then
    printf '   %s✓ สำเร็จ (pm)%s\n' "$G" "$N"; log INFO "ติดตั้ง $name สำเร็จ (pm)"; return 0
  fi

  # วิธี 2: pm --user 0
  out=$(pm install -r -t -g --user 0 "$apk" 2>&1); rc=$?
  if printf '%s' "$out" | grep -qiE 'success|Success' || [ $rc -eq 0 ]; then
    printf '   %s✓ สำเร็จ (pm --user 0)%s\n' "$G" "$N"; log INFO "ติดตั้ง $name สำเร็จ (pm --user 0)"; return 0
  fi

  # วิธี 3: root
  if command -v su >/dev/null 2>&1; then
    out=$(su -c "pm install -r -t -g '$apk'" 2>&1); rc=$?
    if printf '%s' "$out" | grep -qiE 'success|Success' || [ $rc -eq 0 ]; then
      printf '   %s✓ สำเร็จ (root)%s\n' "$G" "$N"; log INFO "ติดตั้ง $name สำเร็จ (root)"; return 0
    fi
    out=$(su -c "pm install -r -t -g --user 0 '$apk'" 2>&1); rc=$?
    if printf '%s' "$out" | grep -qiE 'success|Success' || [ $rc -eq 0 ]; then
      printf '   %s✓ สำเร็จ (root --user 0)%s\n' "$G" "$N"; log INFO "ติดตั้ง $name สำเร็จ (root --user 0)"; return 0
    fi
  fi

  # วิธี 4: cmd package
  out=$(cmd package install -r -t "$apk" 2>&1); rc=$?
  if printf '%s' "$out" | grep -qiE 'success|Success' || [ $rc -eq 0 ]; then
    printf '   %s✓ สำเร็จ (cmd)%s\n' "$G" "$N"; log INFO "ติดตั้ง $name สำเร็จ (cmd)"; return 0
  fi

  # วิธี 5: session
  sid=$(pm install-create 2>/dev/null | grep -oE '[0-9]+' | head -n1)
  if [ -n "$sid" ]; then
    pm install-write "$sid" base.apk "$apk" >/dev/null 2>&1
    out=$(pm install-commit "$sid" 2>&1)
    if printf '%s' "$out" | grep -qiE 'success|Success'; then
      printf '   %s✓ สำเร็จ (session)%s\n' "$G" "$N"; log INFO "ติดตั้ง $name สำเร็จ (session)"; return 0
    fi
  fi

  printf '   %s✗ ติดตั้งล้มเหลวทุกวิธี%s\n' "$R" "$N"
  printf '   %s%s%s\n' "$DIM" "$(trunc "$out" 180)" "$N"
  log ERROR "ติดตั้ง $name ล้มเหลว: $out"
  return 1
}

menu_installer() {
  local c i names=("${!APK_URLS[@]}")
  while true; do
    banner
    printf '%sPROCYSIS AUTO INSTALLER (GitHub)%s\n\n' "$Y" "$N"
    printf ' 1) ติดตั้งทีละตัว\n'
    printf ' 2) ติดตั้งทั้งหมดต่อเนื่อง\n'
    printf ' 3) ดูรายการ\n'
    printf ' 0) กลับ\n\n'
    read -rp "เลือก: " c || return
    case "$c" in
      1|2|3)
        printf '\n'
        for i in "${!names[@]}"; do
          printf '  %s) %s\n' "$((i+1))" "${names[$i]}"
        done
        printf '\n'
        if [ "$c" = "3" ]; then pause; continue; fi
        if [ "$c" = "1" ]; then
          ask "เลขตัวที่ต้องการ" ""
          idx=$((10#$REPLY_VAL - 1))
          if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#names[@]}" ]; then
            name="${names[$idx]}"
            dest="$INSTALL_DIR/$name"
            if download_apk "$name" "$dest"; then
              install_apk "$dest" "$name"
              rm -f "$dest"
            fi
          fi
        else
          for name in "${names[@]}"; do
            printf '\n%s%s%s\n' "$C" "$name" "$N"
            dest="$INSTALL_DIR/$name"
            if download_apk "$name" "$dest"; then
              install_apk "$dest" "$name"
              rm -f "$dest"
            fi
            sleep 2
          done
        fi
        pause ;;
      0) return ;;
    esac
  done
}

main() {
  local c
  check_deps
  rotate_log
  log INFO "===== เปิดโปรแกรม PROCYSIS ====="
  trap on_int INT
  if [ "$(cfg_get USE_ROOT 0)" = "1" ] && have_su; then
    printf '%s⏳ กำลังเชื่อมต่อ root (ครั้งแรกอาจใช้เวลาสักครู่)...%s\n' "$DIM" "$N"
    if rootsh_start; then printf ' %s✓ root พร้อมใช้งาน%s\n' "$G" "$N"
    else printf ' %s✗ เชื่อมต่อ root ไม่ได้ จะใช้ su ทีละคำสั่งแทน (ช้ากว่า)%s\n' "$Y" "$N"; fi
    sleep 1
  fi
  while true; do
    banner
    printf ' 1) เข้าเกม Game ID / VIP Server (เหมือนกันทุกจอที่เปิดใช้งาน)\n'
    printf ' 2) เข้าเกม Game ID / VIP Server (แยกแพ็กเกจ)\n'
    printf ' 3) เปิด Roblox ทุกจอที่เปิดใช้งาน\n'
    printf ' 4) Webhook แจ้งข้อมูล\n'
    printf ' 5) Log บันทึกผลและบัค\n'
    printf ' 6) ออกจากโปรแกรม\n'
    printf ' 7) จัดการเปิด/ปิด Roblox รายจอ\n'
    printf ' 8) เข้าเซิร์ฟด้วยรหัส / ตามเพื่อน (User ID)\n'
    printf ' 9) Auto Rejoin (เฝ้าจอ + เข้าเกมใหม่อัตโนมัติ)\n'
    printf ' a) Android 12 / โหมดหน้าต่าง (แยกจออิสระ)\n'
    printf ' c) คุกกี้ / ล็อกอินอัตโนมัติ / ตรวจรีจอยจากคุกกี้\n'
    printf ' e) Auto Execute (รันสคริปต์อัตโนมัติตอนเข้าเกม)\n'
    printf ' p) โปรไฟล์ (บันทึก/สลับชุดตั้งค่า)\n'
    printf ' d) แดชบอร์ดสถานะสด (ตารางทุกจอ)\n'
    printf ' f) โหมดประหยัดสเปก (ลดแลก กราฟิกต่ำ/ล็อก FPS)\n'
    printf ' r) บัญชี / Robux (ติดตามยอด + เตือนบัญชีมีปัญหา)\n'
    printf ' s) ตั้งค่า\n\n'
    printf ' i) ติดตั้ง APK อัตโนมัติ (GitHub)\n'
    read -rp "เลือกเมนู: " c || on_exit
    case "$c" in
      1) menu_same ;;
      2) menu_separate ;;
      3) menu_open ;;
      4) menu_webhook ;;
      5) menu_log ;;
      6|0|q|Q) on_exit ;;
      7) menu_screen_control ;;
      8) menu_join_server ;;
      9) menu_rejoin ;;
      a|A) menu_android12 ;;
      c|C) menu_cookie ;;
      e|E) menu_autoexec ;;
      p|P) menu_profiles ;;
      d|D) menu_dashboard ;;
      f|F) menu_perf ;;
      r|R) menu_accounts ;;
      s|S) menu_settings ;;
      i|I) menu_installer ;;
    esac
  done
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi
