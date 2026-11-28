#!/usr/bin/env bash
# Power Home Coach 94.2.9.1: staged build, isolated smoke test, backup and rollback.
set -Eeuo pipefail
umask 077
TARGET=/opt/power-home-coach
STAGE=/opt/power-home-staging/r94291
SOURCE="$STAGE/source"
RUNTIME="$STAGE/runtime"
ARCHIVE_SHA=e9f1c648960394018cfbcd4edef700766c7dbe149571e6a31b718cb21cda1563
IMAGE=power-home-coach-app:r94291
LIVE_IMAGE=power-home-coach-app:latest
ROLLBACK_IMAGE=power-home-coach-app:rollback-r94291-20261128
SMOKE=power-home-r94291-smoke
CODE_COMMIT=${1:?Supply the reviewed source commit}
[[ $CODE_COMMIT =~ ^[a-f0-9]{40}$ ]] || { echo 'A pinned40-character commit is required'; exit 1; }
[[ $CODE_COMMIT == a89f5f3a21418d28a9a7e1a4a0b74e23f8a822ff ]] || { echo 'Source commit mismatch'; exit 1; }
# Official GitHub Git-blob API avoids the raw-content host that timed out on this server.
fetch_release_blob() {
  local blob_sha=$1 destination=$2
  curl -4 --http1.1 -fLsS --retry 2 --connect-timeout 15 --max-time 240 "https://api.github.com/repos/arminsorkheii-spec/power-home-coach/git/blobs/$blob_sha" -o "$destination.json"
  python3 - "$destination.json" "$destination" "$blob_sha" <<'PYBLOB'
import pathlib,json,base64,hashlib,sys
payload,dest,expected=sys.argv[1:];data=json.loads(pathlib.Path(payload).read_text());assert data.get('encoding')=='base64' and data.get('sha')==expected
raw=base64.b64decode(data['content']);assert hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==expected
pathlib.Path(dest).write_bytes(raw);pathlib.Path(payload).unlink();print('PINNED GIT BLOB VERIFIED',expected)
PYBLOB
}
MEDIA_SHA=378780658669793247fc6835196380c2746226d6246a86c112dec3f9c359f136
[[ $EUID == 0 && -d "$TARGET/data" && -f "$TARGET/compose.yaml" && -f "$TARGET/.env" ]]
curl -fLsS --max-time 30 https://arminsorkhei.ir/sw.js | grep -q '94.2.9' || { echo 'BASELINE MISMATCH: expected94.2.9'; exit 1; }
[[ $(df -Pk /opt | awk 'NR==2 {print $4}') -gt 2000000 ]] || { echo 'Need2GB free staging space'; exit 1; }
mkdir -p "$STAGE" /opt/power-home-backups
exec > >(tee -a "$STAGE/install.log") 2>&1
cd "$TARGET"
[[ ! -f "$STAGE/installed.ok" ]] || { echo 'ALREADY INSTALLED'; exit 0; }
DEPLOY_BACKUP=$(mktemp -d /opt/power-home-backups/r94291-20261128-XXXXXX)
printf '%s\n' "$DEPLOY_BACKUP" > "$STAGE/backup-path"
cp -a compose.yaml Caddyfile .env "$DEPLOY_BACKUP/"
OLD_CONTAINER=$(docker compose ps -q app)
[[ -n "$OLD_CONTAINER" ]]
OLD_IMAGE=$(docker inspect --format '{{.Image}}' "$OLD_CONTAINER")
docker tag "$OLD_IMAGE" "$ROLLBACK_IMAGE"
SWITCHED=0
STOPPED=0
on_error() {
  code=$?
  trap - ERR
  echo "INSTALL FAILED: $code"
  docker rm -f "$SMOKE" >/dev/null 2>&1 || true
  if [[ $SWITCHED == 1 ]]; then cp -a "$DEPLOY_BACKUP/compose.yaml" "$TARGET/compose.yaml"; docker tag "$ROLLBACK_IMAGE" "$LIVE_IMAGE"; docker compose up -d --no-build --force-recreate app || true
  elif [[ $STOPPED == 1 ]]; then cp -a "$DEPLOY_BACKUP/compose.yaml" "$TARGET/compose.yaml"; docker compose start app || true
  fi
  echo "BACKUP: $DEPLOY_BACKUP"
  exit "$code"
}
trap on_error ERR
printf 'STAGE 1: verify installed baseline and prepare reviewed playback guidance\n'
python3 - "$SOURCE" <<'PYUPDATE'
import pathlib,shutil,hashlib,base64,json,sys
base=pathlib.Path('/opt/power-home-staging/r9429/source');dest=pathlib.Path(sys.argv[1])
assert '94.2.9' in (base/'lib/pwa-client.ts').read_text()
assert hashlib.sha256((base/'components/exercise-video-button.tsx').read_bytes()).hexdigest()=='953d65ba17d439626de759d72e741799965f76744583adbede88636c15d0695e'
shutil.copytree(base,dest,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.next','node_modules','.git'))
for name,encoded in json.loads('{"components/exercise-video-button.tsx": "InVzZSBjbGllbnQiOwoKaW1wb3J0ICogYXMgUmVhY3QgZnJvbSAicmVhY3QiOwppbXBvcnQgeyBBbGVydENpcmNsZSwgUGxheSwgVmlkZW8gfSBmcm9tICJsdWNpZGUtcmVhY3QiOwppbXBvcnQgeyB2aW1lb0V4ZXJjaXNlRW1iZWRVcmwgfSBmcm9tICJAL2xpYi9leGVyY2lzZS12aWRlby1zb3VyY2UiOwppbXBvcnQgewogIERpYWxvZywKICBEaWFsb2dDb250ZW50LAogIERpYWxvZ0Rlc2NyaXB0aW9uLAogIERpYWxvZ0hlYWRlciwKICBEaWFsb2dUaXRsZSwKICBEaWFsb2dUcmlnZ2VyLAp9IGZyb20gIkAvY29tcG9uZW50cy91aS9kaWFsb2ciOwoKZXhwb3J0IHR5cGUgTWFsZUV4ZXJjaXNlVmlkZW8gPSB7CiAgLyoqIEEgbWFsZS1vbmx5IHZpZGVvIGF1dGhvcml6ZWQgZm9yIHVzZSBpbiBQb3dlciBIb21lIENvYWNoLiAqLwogIG1hbGVWaWRlb1VybD86IHN0cmluZzsKICAvKiogUHVibGljLCBtYWxlLW9ubHkgc291cmNlIHdpdGggZW1iZWRkaW5nIGVuYWJsZWQgYnkgaXRzIG93bmVyLiAqLwogIG1hbGVWaW1lb0lkPzogc3RyaW5nIHwgbnVsbDsKICB2YXJpYW50Tm90ZT86IHN0cmluZyB8IG51bGw7CiAgbWFsZVBvc3RlclVybD86IHN0cmluZyB8IG51bGw7CiAgYXR0cmlidXRpb24/OiBzdHJpbmcgfCBudWxsOwogIGF0dHJpYnV0aW9uVXJsPzogc3RyaW5nIHwgbnVsbDsKICBsaWNlbnNlVXJsPzogc3RyaW5nIHwgbnVsbDsKfTsKCmV4cG9ydCB0eXBlIEV4ZXJjaXNlVmlkZW9CdXR0b25Qcm9wcyA9IHsKICBleGVyY2lzZU5hbWU6IHN0cmluZzsKICB2aWRlbz86IE1hbGVFeGVyY2lzZVZpZGVvIHwgbnVsbDsKICBjbGFzc05hbWU/OiBzdHJpbmc7Cn07CgpmdW5jdGlvbiBzYWZlTWVkaWFVcmwoY2FuZGlkYXRlPzogc3RyaW5nIHwgbnVsbCk6IHN0cmluZyB8IHVuZGVmaW5lZCB7CiAgaWYgKCFjYW5kaWRhdGUpIHJldHVybiB1bmRlZmluZWQ7CiAgY29uc3QgdmFsdWUgPSBjYW5kaWRhdGUudHJpbSgpOwogIGlmICghdmFsdWUgfHwgdmFsdWUuc3RhcnRzV2l0aCgiLy8iKSB8fCB2YWx1ZS5zdGFydHNXaXRoKCJcXCIpKSByZXR1cm4gdW5kZWZpbmVkOwogIGlmICh2YWx1ZS5zdGFydHNXaXRoKCIvIikgJiYgIXZhbHVlLmluY2x1ZGVzKCJcXCIpICYmICF2YWx1ZS5pbmNsdWRlcygiLi4iKSkgcmV0dXJuIHZhbHVlOwogIHRyeSB7CiAgICBjb25zdCBwYXJzZWQgPSBuZXcgVVJMKHZhbHVlKTsKICAgIHJldHVybiBwYXJzZWQucHJvdG9jb2wgPT09ICJodHRwczoiID8gcGFyc2VkLnRvU3RyaW5nKCkgOiB1bmRlZmluZWQ7CiAgfSBjYXRjaCB7CiAgICByZXR1cm4gdW5kZWZpbmVkOwogIH0KfQoKLyoqCiAqIEFkZCB0byB0aGUgc3R1ZGVudCB3b3Jrb3V0IHJvdyBuZXh0IHRvIHRoZSBleGVyY2lzZSBuYW1lLgogKiBSZW5kZXJzIG5vIGJ1dHRvbiBpZiBhIHZlcmlmaWVkIG1hbGUtb25seSB2aWRlbyBoYXMgbm90IGJlZW4gYXNzaWduZWQuCiAqIERvZXMgbm90IGFsdGVyIGV4aXN0aW5nIHdvcmtvdXQgcm93cywgcHJpbnQgb3V0cHV0LCBvciBleGVyY2lzZSBkYXRhLgogKi8KZXhwb3J0IGZ1bmN0aW9uIEV4ZXJjaXNlVmlkZW9CdXR0b24oewogIGV4ZXJjaXNlTmFtZSwKICB2aWRlbywKICBjbGFzc05hbWUsCn06IEV4ZXJjaXNlVmlkZW9CdXR0b25Qcm9wcykgewogIGNvbnN0IFtvcGVuLCBzZXRPcGVuXSA9IFJlYWN0LnVzZVN0YXRlKGZhbHNlKTsKICBjb25zdCBbZmFpbGVkLCBzZXRGYWlsZWRdID0gUmVhY3QudXNlU3RhdGUoZmFsc2UpOwogIGNvbnN0IFthdHRlbXB0LHNldEF0dGVtcHRdPVJlYWN0LnVzZVN0YXRlKDApOwogIGNvbnN0IHZpZGVvVXJsID0gc2FmZU1lZGlhVXJsKHZpZGVvPy5tYWxlVmlkZW9VcmwpOwogIGNvbnN0IGVtYmVkVXJsID0gdmltZW9FeGVyY2lzZUVtYmVkVXJsKHZpZGVvPy5tYWxlVmltZW9JZCk7CiAgY29uc3QgcG9zdGVyVXJsID0gc2FmZU1lZGlhVXJsKHZpZGVvPy5tYWxlUG9zdGVyVXJsKTsKCiAgUmVhY3QudXNlRWZmZWN0KCgpID0+IHsKICAgIGlmIChvcGVuKSBzZXRGYWlsZWQoZmFsc2UpOwogIH0sIFtvcGVuLCB2aWRlb1VybCwgZW1iZWRVcmxdKTsKCiAgaWYgKCF2aWRlb1VybCAmJiAhZW1iZWRVcmwpIHJldHVybiBudWxsOwoKICByZXR1cm4gKAogICAgPERpYWxvZyBvcGVuPXtvcGVufSBvbk9wZW5DaGFuZ2U9e3NldE9wZW59PgogICAgICA8RGlhbG9nVHJpZ2dlciBhc0NoaWxkPgogICAgICAgIDxidXR0b24KICAgICAgICAgIHR5cGU9ImJ1dHRvbiIKICAgICAgICAgIGNsYXNzTmFtZT17WwogICAgICAgICAgICAiaW5saW5lLWZsZXggbWluLWgtMTAgaXRlbXMtY2VudGVyIGp1c3RpZnktY2VudGVyIGdhcC0yIHJvdW5kZWQteGwgYm9yZGVyIiwKICAgICAgICAgICAgImJvcmRlci16aW5jLTYwMCBiZy16aW5jLTgwMCBweC0zIHB5LTIgdGV4dC1zbSBmb250LXNlbWlib2xkIHRleHQtemluYy0xMDAiLAogICAgICAgICAgICAidHJhbnNpdGlvbi1jb2xvcnMgaG92ZXI6Ym9yZGVyLXppbmMtNDAwIGhvdmVyOmJnLXppbmMtNzAwIiwKICAgICAgICAgICAgImZvY3VzLXZpc2libGU6b3V0bGluZSBmb2N1cy12aXNpYmxlOm91dGxpbmUtMiBmb2N1cy12aXNpYmxlOm91dGxpbmUtb2Zmc2V0LTIgZm9jdXMtdmlzaWJsZTpvdXRsaW5lLXJlZC01MDAiLAogICAgICAgICAgICBjbGFzc05hbWUgPz8gIiIsCiAgICAgICAgICBdLmpvaW4oIiAiKX0KICAgICAgICAgIGFyaWEtbGFiZWw9e2DZvtiu2LQg2YjbjNiv2KbZiNuMINit2LHaqdiqICR7ZXhlcmNpc2VOYW1lfWB9CiAgICAgICAgPgogICAgICAgICAgPFBsYXkgYXJpYS1oaWRkZW49InRydWUiIGNsYXNzTmFtZT0iaC00IHctNCIgZmlsbD0iY3VycmVudENvbG9yIiAvPgogICAgICAgICAg2YbZhdin24zYtCDZiNuM2K/YptmICiAgICAgICAgPC9idXR0b24+CiAgICAgIDwvRGlhbG9nVHJpZ2dlcj4KICAgICAgPERpYWxvZ0NvbnRlbnQKICAgICAgICBkaXI9InJ0bCIKICAgICAgICBjbGFzc05hbWU9ImV4ZXJjaXNlLXZpZGVvLWRpYWxvZyB3LVttaW4oOTV2dyw2ODBweCldIG1heC13LVs2ODBweF0gZ2FwLTMgYm9yZGVyLXppbmMtNzAwIGJnLXppbmMtOTUwIHAtNCB0ZXh0LXppbmMtMTAwIHNtOnAtNSIKICAgICAgPgogICAgICAgIDxEaWFsb2dIZWFkZXIgY2xhc3NOYW1lPSJwci0xIHRleHQtcmlnaHQgc206dGV4dC1yaWdodCI+CiAgICAgICAgICA8RGlhbG9nVGl0bGUgY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMiB0ZXh0LWJhc2UgZm9udC1ib2xkIHNtOnRleHQtbGciPgogICAgICAgICAgICA8VmlkZW8gY2xhc3NOYW1lPSJoLTUgdy01IHRleHQtcmVkLTUwMCIgYXJpYS1oaWRkZW49InRydWUiIC8+CiAgICAgICAgICAgIHtleGVyY2lzZU5hbWV9CiAgICAgICAgICA8L0RpYWxvZ1RpdGxlPgogICAgICAgICAgPERpYWxvZ0Rlc2NyaXB0aW9uIGNsYXNzTmFtZT0idGV4dC1yaWdodCB0ZXh0LXhzIHRleHQtemluYy00MDAiPgogICAgICAgICAgICDZiNuM2K/YptmI24wg2KLZhdmI2LLYtNuMINin2KzYsdin24wg2LXYrduM2K0g2K3Ysdqp2Kog4oCUINmF2K/ZhCDZhdix2K/Yp9mG2YcKICAgICAgICAgIDwvRGlhbG9nRGVzY3JpcHRpb24+CiAgICAgICAgPC9EaWFsb2dIZWFkZXI+CiAgICAgICAgPGRpdiBjbGFzc05hbWU9Im92ZXJmbG93LWhpZGRlbiByb3VuZGVkLXhsIGJvcmRlciBib3JkZXItemluYy04MDAgYmctYmxhY2siPgogICAgICAgICAge29wZW4gJiYgIWZhaWxlZCA/ICgKICAgICAgICAgICAgdmlkZW9VcmwgPyA8dmlkZW8KICAgICAgICAgICAgICBrZXk9e3ZpZGVvVXJsK2F0dGVtcHR9CiAgICAgICAgICAgICAgY29udHJvbHMKICAgICAgICAgICAgICBwbGF5c0lubGluZQogICAgICAgICAgICAgIHByZWxvYWQ9Im1ldGFkYXRhIgogICAgICAgICAgICAgIHBvc3Rlcj17cG9zdGVyVXJsfQogICAgICAgICAgICAgIGNsYXNzTmFtZT0iYXNwZWN0LXZpZGVvIHctZnVsbCBiZy1ibGFjayBvYmplY3QtY29udGFpbiIKICAgICAgICAgICAgICBhcmlhLWxhYmVsPXtg2YjbjNiv2KbZiNuMINin2KzYsdin24wgJHtleGVyY2lzZU5hbWV9YH0KICAgICAgICAgICAgICBvbkVycm9yPXsoKSA9PiBzZXRGYWlsZWQodHJ1ZSl9CiAgICAgICAgICAgID4KICAgICAgICAgICAgICA8c291cmNlIHNyYz17dmlkZW9Vcmx9IC8+CiAgICAgICAgICAgICAg2YXYsdmI2LHar9ixINi02YXYpyDYp9iyINm+2K7YtCDYp9uM2YYg2YjbjNiv2KbZiCDZvti02KrbjNio2KfZhtuMINmG2YXbjOKAjNqp2YbYry4KICAgICAgICAgICAgPC92aWRlbz4gOiA8aWZyYW1lCiAgICAgICAgICAgICAga2V5PXtlbWJlZFVybCtTdHJpbmcoYXR0ZW1wdCl9CiAgICAgICAgICAgICAgc3JjPXtlbWJlZFVybH0KICAgICAgICAgICAgICB0aXRsZT17YNmI24zYr9im2YjbjCDYp9is2LHYp9uMICR7ZXhlcmNpc2VOYW1lfWB9CiAgICAgICAgICAgICAgY2xhc3NOYW1lPSJhc3BlY3QtdmlkZW8gdy1mdWxsIGJvcmRlci0wIGJnLWJsYWNrIgogICAgICAgICAgICAgIGxvYWRpbmc9ImxhenkiCiAgICAgICAgICAgICAgYWxsb3c9ImZ1bGxzY3JlZW47IHBpY3R1cmUtaW4tcGljdHVyZSIKICAgICAgICAgICAgICBhbGxvd0Z1bGxTY3JlZW4KICAgICAgICAgICAgICBzYW5kYm94PSJhbGxvdy1zY3JpcHRzIGFsbG93LXNhbWUtb3JpZ2luIGFsbG93LXByZXNlbnRhdGlvbiIKICAgICAgICAgICAgICByZWZlcnJlclBvbGljeT0ic3RyaWN0LW9yaWdpbi13aGVuLWNyb3NzLW9yaWdpbiIKICAgICAgICAgICAgICBvbkVycm9yPXsoKSA9PiBzZXRGYWlsZWQodHJ1ZSl9CiAgICAgICAgICAgIC8+CiAgICAgICAgICApIDogKAogICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBhc3BlY3QtdmlkZW8gZmxleC1jb2wgaXRlbXMtY2VudGVyIGp1c3RpZnktY2VudGVyIGdhcC0zIHAtNiB0ZXh0LWNlbnRlciB0ZXh0LXNtIHRleHQtemluYy0zMDAiIHJvbGU9ImFsZXJ0Ij4KICAgICAgICAgICAgICA8QWxlcnRDaXJjbGUgY2xhc3NOYW1lPSJoLTcgdy03IHRleHQtYW1iZXItNDAwIiBhcmlhLWhpZGRlbj0idHJ1ZSIgLz4KICAgICAgICAgICAgICDYqNin2LHar9iw2KfYsduMINmI24zYr9im2Ygg2KfZhdqp2KfZhuKAjNm+2LDbjNixINmG24zYs9iqLiDZhNi32YHYp9mLINio2LnYr9in2Ysg2K/ZiNio2KfYsdmHINin2YXYqtit2KfZhiDaqdmG24zYry4KICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICApfQogICAgICAgIDwvZGl2PgogICAgICAgIHtlbWJlZFVybCYmIXZpZGVvVXJsJiY8cCBjbGFzc05hbWU9InRleHQtcmlnaHQgdGV4dC14cyBsZWFkaW5nLTYgdGV4dC16aW5jLTMwMCI+2KfbjNmGINmI24zYr9im2Ygg2KfYsiDZhdmG2KjYuSDYrtin2LHYrNuMINm+2K7YtCDZhduM4oCM2LTZiNiv2Jsg2K/Ys9iq2LHYs9uMINii2YYg2KjZhyDYp9iq2LXYp9mEINin24zZhtiq2LHZhtiqINio2LPYqtqv24wg2K/Yp9ix2K8uINin2q/YsSDZvtmG2KzYsdmHINiu2KfZhNuMINmF2KfZhtiv2Iwg2K/ZiNio2KfYsdmHINiq2YTYp9i0INqp2YYg24zYpyDZhNuM2YbaqSDZhdmG2KjYuSDYsdinINio2KfYsiDaqdmGLjwvcD59CiAgICAgICAgeyhmYWlsZWR8fEJvb2xlYW4oZW1iZWRVcmwmJiF2aWRlb1VybCkpJiY8YnV0dG9uIHR5cGU9ImJ1dHRvbiIgb25DbGljaz17KCk9PntzZXRGYWlsZWQoZmFsc2UpO3NldEF0dGVtcHQodmFsdWU9PnZhbHVlKzEpfX0+2KrZhNin2LQg2K/ZiNio2KfYsdmHINio2LHYp9uMINm+2K7YtDwvYnV0dG9uPn0KICAgICAgICB7dmlkZW8/LnZhcmlhbnROb3RlICYmIDxwIGNsYXNzTmFtZT0idGV4dC1yaWdodCB0ZXh0LXhzIGxlYWRpbmctNiB0ZXh0LXppbmMtMzAwIj57dmlkZW8udmFyaWFudE5vdGV9PC9wPn0KICAgICAgICB7dmlkZW8/LmF0dHJpYnV0aW9uID8gKAogICAgICAgICAgPHAgY2xhc3NOYW1lPSJ0ZXh0LWNlbnRlciB0ZXh0LXhzIHRleHQtemluYy00MDAiPnt2aWRlby5hdHRyaWJ1dGlvbn17c2FmZU1lZGlhVXJsKHZpZGVvLmF0dHJpYnV0aW9uVXJsKSAmJiA8PiDCtyA8YSBocmVmPXtzYWZlTWVkaWFVcmwodmlkZW8uYXR0cmlidXRpb25VcmwpfSB0YXJnZXQ9Il9ibGFuayIgcmVsPSJub29wZW5lciBub3JlZmVycmVyIiBjbGFzc05hbWU9InVuZGVybGluZSI+2YXZhtio2Lk8L2E+PC8+fXtzYWZlTWVkaWFVcmwodmlkZW8ubGljZW5zZVVybCkgJiYgPD4gwrcgPGEgaHJlZj17c2FmZU1lZGlhVXJsKHZpZGVvLmxpY2Vuc2VVcmwpfSB0YXJnZXQ9Il9ibGFuayIgcmVsPSJub29wZW5lciBub3JlZmVycmVyIiBjbGFzc05hbWU9InVuZGVybGluZSI+2LTYsdin24zYtyDYp9iz2KrZgdin2K/ZhzwvYT48Lz59PC9wPgogICAgICAgICkgOiBudWxsfQogICAgICA8L0RpYWxvZ0NvbnRlbnQ+CiAgICA8L0RpYWxvZz4KICApOwp9Cg==", "lib/pwa-client.ts": "ZXhwb3J0IGNvbnN0IEFQUF9SRUxFQVNFID0gIjk0LjIuOS4xIjsKCmV4cG9ydCBmdW5jdGlvbiBib3VuZGVkPFQ+KG9wZXJhdGlvbjogUHJvbWlzZTxUPiwgbWlsbGlzZWNvbmRzID0gMTIwMDApOiBQcm9taXNlPFQ+IHsKICByZXR1cm4gbmV3IFByb21pc2UoKHJlc29sdmUsIHJlamVjdCkgPT4gewogICAgY29uc3QgdGltZXIgPSBzZXRUaW1lb3V0KCgpID0+IHJlamVjdChuZXcgRXJyb3IoItiy2YXYp9mGINin2YbYqti42KfYsSDYqtmF2KfZhSDYtNiv2Jsg2K/ZiNio2KfYsdmHINiq2YTYp9i0INqp2YbbjNivLiIpKSwgbWlsbGlzZWNvbmRzKTsKICAgIG9wZXJhdGlvbi50aGVuKHJlc29sdmUsIHJlamVjdCkuZmluYWxseSgoKSA9PiBjbGVhclRpbWVvdXQodGltZXIpKTsKICB9KTsKfQoKbGV0IHJlZ2lzdHJhdGlvbjogUHJvbWlzZTxTZXJ2aWNlV29ya2VyUmVnaXN0cmF0aW9uPiB8IHVuZGVmaW5lZDsKZXhwb3J0IGZ1bmN0aW9uIGFwcFNlcnZpY2VXb3JrZXIoKSB7CiAgaWYgKCFyZWdpc3RyYXRpb24pIHsKICAgIHJlZ2lzdHJhdGlvbiA9IGJvdW5kZWQobmF2aWdhdG9yLnNlcnZpY2VXb3JrZXIucmVnaXN0ZXIoYC9zdy5qcz92PSR7QVBQX1JFTEVBU0V9YCwgeyB1cGRhdGVWaWFDYWNoZTogIm5vbmUiIH0pKQogICAgICAuY2F0Y2goZXJyb3IgPT4geyByZWdpc3RyYXRpb24gPSB1bmRlZmluZWQ7IHRocm93IGVycm9yOyB9KTsKICB9CiAgcmV0dXJuIHJlZ2lzdHJhdGlvbjsKfQoKZXhwb3J0IGZ1bmN0aW9uIHBvcnRhbEZldGNoKHVybDogc3RyaW5nLCBvcHRpb25zOiBSZXF1ZXN0SW5pdCA9IHt9KSB7CiAgcmV0dXJuIGZldGNoKHVybCwgeyAuLi5vcHRpb25zLCBzaWduYWw6IEFib3J0U2lnbmFsLnRpbWVvdXQoMTIwMDApIH0pLnRoZW4ocmVzcG9uc2U9PntpZihyZXNwb25zZS5vayYmIVsiR0VUIiwiSEVBRCJdLmluY2x1ZGVzKChvcHRpb25zLm1ldGhvZD8/IkdFVCIpLnRvVXBwZXJDYXNlKCkpJiZ0eXBlb2Ygd2luZG93IT09J3VuZGVmaW5lZCcpd2luZG93LmRpc3BhdGNoRXZlbnQobmV3IEV2ZW50KCdwb3dlci1kYXRhLXVwZGF0ZWQnKSk7cmV0dXJuIHJlc3BvbnNlfSk7Cn0K", "public/sw.js": "Y29uc3QgQkFER0VfQ0FDSEUgPSAiYXJtaW4tY29hY2gtYmFkZ2UtdjEiOwpjb25zdCBCQURHRV9LRVkgPSAiL19fYXBwLWJhZGdlLWNvdW50X18iOwpjb25zdCBTV19SRUxFQVNFID0gIjk0LjIuOS4xIjsKCnNlbGYuYWRkRXZlbnRMaXN0ZW5lcigiaW5zdGFsbCIsICgpID0+IHsKICBzZWxmLnNraXBXYWl0aW5nKCk7Cn0pOwoKc2VsZi5hZGRFdmVudExpc3RlbmVyKCJhY3RpdmF0ZSIsIChldmVudCkgPT4gewogIGV2ZW50LndhaXRVbnRpbCgoYXN5bmMgKCkgPT4gewogICAgY29uc3QgY2FjaGVOYW1lcyA9IGF3YWl0IGNhY2hlcy5rZXlzKCk7CiAgICBhd2FpdCBQcm9taXNlLmFsbChjYWNoZU5hbWVzLmZpbHRlcigobmFtZSkgPT4gbmFtZSAhPT0gQkFER0VfQ0FDSEUpLm1hcCgobmFtZSkgPT4gY2FjaGVzLmRlbGV0ZShuYW1lKSkpOwogICAgYXdhaXQgc2VsZi5jbGllbnRzLmNsYWltKCk7CiAgICAvLyBBY3RpdmF0aW9uIG11c3QgbmV2ZXIgcmVsb2FkIG9wZW4gZm9ybXMgb3Igbm90aWZpY2F0aW9uIHNjcmVlbnMuCiAgfSkoKSk7Cn0pOwoKYXN5bmMgZnVuY3Rpb24gcmVhZEJhZGdlQ291bnQoKSB7CiAgY29uc3QgY2FjaGUgPSBhd2FpdCBjYWNoZXMub3BlbihCQURHRV9DQUNIRSk7CiAgY29uc3Qgc3RvcmVkID0gYXdhaXQgY2FjaGUubWF0Y2goQkFER0VfS0VZKTsKICBpZiAoIXN0b3JlZCkgcmV0dXJuIDA7CiAgY29uc3QgdmFsdWUgPSBOdW1iZXIoYXdhaXQgc3RvcmVkLnRleHQoKSk7CiAgcmV0dXJuIE51bWJlci5pc0Zpbml0ZSh2YWx1ZSkgPyB2YWx1ZSA6IDA7Cn0KCmFzeW5jIGZ1bmN0aW9uIHNob3dCYWRnZShjb3VudCkgewogIGNvbnN0IGNhY2hlID0gYXdhaXQgY2FjaGVzLm9wZW4oQkFER0VfQ0FDSEUpOwogIGF3YWl0IGNhY2hlLnB1dChCQURHRV9LRVksIG5ldyBSZXNwb25zZShTdHJpbmcoTWF0aC5tYXgoMCwgY291bnQpKSkpOwogIGlmIChjb3VudCA+IDAgJiYgInNldEFwcEJhZGdlIiBpbiBzZWxmLnJlZ2lzdHJhdGlvbikgewogICAgYXdhaXQgc2VsZi5yZWdpc3RyYXRpb24uc2V0QXBwQmFkZ2UoY291bnQpOwogIH0gZWxzZSBpZiAoY291bnQgPT09IDAgJiYgImNsZWFyQXBwQmFkZ2UiIGluIHNlbGYucmVnaXN0cmF0aW9uKSB7CiAgICBhd2FpdCBzZWxmLnJlZ2lzdHJhdGlvbi5jbGVhckFwcEJhZGdlKCk7CiAgfQp9CgpzZWxmLmFkZEV2ZW50TGlzdGVuZXIoInB1c2giLCAoZXZlbnQpID0+IHsKICBsZXQgZGF0YSA9IHsgdGl0bGU6ICLYotix2YXbjNmGINiz2LHYrtmH4oCM2KfbjCIsIGJvZHk6ICLYp9i52YTYp9mGINis2K/bjNivIiwgdXJsOiAiLyIsIHRhZzogImFybWluLWNvYWNoIiB9OwogIHRyeSB7IGRhdGEgPSB7IC4uLmRhdGEsIC4uLmV2ZW50LmRhdGEuanNvbigpIH07IH0gY2F0Y2gge30KICBldmVudC53YWl0VW50aWwoKGFzeW5jICgpID0+IHsKICAgIGNvbnN0IG5leHRDb3VudCA9IChhd2FpdCByZWFkQmFkZ2VDb3VudCgpKSArIDE7CiAgICBhd2FpdCBQcm9taXNlLmFsbChbCiAgICAgIHNlbGYucmVnaXN0cmF0aW9uLnNob3dOb3RpZmljYXRpb24oZGF0YS50aXRsZSwgewogICAgICAgIGJvZHk6IGRhdGEuYm9keSwKICAgICAgICBpY29uOiAiL2ljb24tNTEyLnBuZyIsCiAgICAgICAgYmFkZ2U6ICIvYXBwbGUtdG91Y2gtaWNvbi5wbmciLAogICAgICAgIHRhZzogZGF0YS50YWcsCiAgICAgICAgZGF0YTogeyB1cmw6IGRhdGEudXJsLCBub3RpZmljYXRpb25JZDpkYXRhLm5vdGlmaWNhdGlvbklkLCByb2xlOmRhdGEucm9sZSB9LAogICAgICAgIHJlbm90aWZ5OiB0cnVlLAogICAgICB9KSwKICAgICAgc2hvd0JhZGdlKG5leHRDb3VudCksCiAgICBdKTsKICB9KSgpKTsKfSk7CgpzZWxmLmFkZEV2ZW50TGlzdGVuZXIoIm1lc3NhZ2UiLCAoZXZlbnQpID0+IHsKICBpZihldmVudC5kYXRhPy50eXBlPT09IlNFVF9CQURHRSImJk51bWJlci5pc1NhZmVJbnRlZ2VyKGV2ZW50LmRhdGEuY291bnQpJiZldmVudC5kYXRhLmNvdW50Pj0wJiZldmVudC5kYXRhLmNvdW50PD0xMDAwMDApZXZlbnQud2FpdFVudGlsKHNob3dCYWRnZShldmVudC5kYXRhLmNvdW50KSk7CiAgaWYgKGV2ZW50LmRhdGE/LnR5cGUgPT09ICJDTEVBUl9CQURHRSIpIGV2ZW50LndhaXRVbnRpbChzaG93QmFkZ2UoMCkpOwogIGlmIChldmVudC5kYXRhPy50eXBlID09PSAiU0tJUF9XQUlUSU5HIikgc2VsZi5za2lwV2FpdGluZygpOwp9KTsKCnNlbGYuYWRkRXZlbnRMaXN0ZW5lcigibm90aWZpY2F0aW9uY2xpY2siLCAoZXZlbnQpID0+IHsKICBldmVudC5ub3RpZmljYXRpb24uY2xvc2UoKTsKICBsZXQgdGFyZ2V0OwogIHRyeSB7IHRhcmdldCA9IG5ldyBVUkwoZXZlbnQubm90aWZpY2F0aW9uLmRhdGE/LnVybCB8fCAiLyIsIHNlbGYubG9jYXRpb24ub3JpZ2luKTsgfSBjYXRjaCB7IHRhcmdldCA9IG5ldyBVUkwoIi8iLCBzZWxmLmxvY2F0aW9uLm9yaWdpbik7IH0KICBpZih0YXJnZXQub3JpZ2luPT09c2VsZi5sb2NhdGlvbi5vcmlnaW4mJiF0YXJnZXQuc2VhcmNoJiYhdGFyZ2V0Lmhhc2gpewogICAgaWYodGFyZ2V0LnBhdGhuYW1lPT09Ii9jb2FjaCIpdGFyZ2V0LnNlYXJjaD0iP3ZpZXc9bm90aWZpY2F0aW9ucyI7CiAgICBpZih0YXJnZXQucGF0aG5hbWU9PT0iL3N0dWRlbnQiKXRhcmdldC5zZWFyY2g9Ij9zZWN0aW9uPW5vdGlmaWNhdGlvbnMiOwogIH0KICBjb25zdCB1cmwgPSB0YXJnZXQub3JpZ2luID09PSBzZWxmLmxvY2F0aW9uLm9yaWdpbiA/IHRhcmdldC5ocmVmIDogc2VsZi5sb2NhdGlvbi5vcmlnaW4gKyAiLyI7CiAgZXZlbnQud2FpdFVudGlsKFByb21pc2UuYWxsKFsKICAgIChhc3luYygpPT57Y29uc3QgZGF0YT1ldmVudC5ub3RpZmljYXRpb24uZGF0YTtjb25zdCBpZD1kYXRhPy5ub3RpZmljYXRpb25JZCxyb2xlPWRhdGE/LnJvbGU7CiAgICAgIGlmKHR5cGVvZiBpZCE9PSJzdHJpbmcifHwhL15bMC05YS1mLV17MzZ9JC9pLnRlc3QoaWQpfHwhWyJjb2FjaCIsInN0dWRlbnQiXS5pbmNsdWRlcyhyb2xlKSl7YXdhaXQgc2hvd0JhZGdlKE1hdGgubWF4KDAsKGF3YWl0IHJlYWRCYWRnZUNvdW50KCkpLTEpKTtyZXR1cm47fQogICAgICB0cnl7Y29uc3QgcmVzcG9uc2U9YXdhaXQgZmV0Y2goIi9hcGkvbm90aWZpY2F0aW9ucyIse21ldGhvZDoiUEFUQ0giLGNyZWRlbnRpYWxzOiJzYW1lLW9yaWdpbiIsaGVhZGVyczp7ImNvbnRlbnQtdHlwZSI6ImFwcGxpY2F0aW9uL2pzb24iLCJ4LXBvcnRhbC1yb2xlIjpyb2xlfSxib2R5OkpTT04uc3RyaW5naWZ5KHtpZHM6W2lkXX0pfSk7aWYocmVzcG9uc2Uub2spe2NvbnN0IHJlc3VsdD1hd2FpdCByZXNwb25zZS5qc29uKCk7aWYoTnVtYmVyLmlzU2FmZUludGVnZXIocmVzdWx0LnVucmVhZCkmJnJlc3VsdC51bnJlYWQ+PTApYXdhaXQgc2hvd0JhZGdlKHJlc3VsdC51bnJlYWQpO319Y2F0Y2h7fQogICAgfSkoKSwKICAgIGNsaWVudHMubWF0Y2hBbGwoeyB0eXBlOiAid2luZG93IiwgaW5jbHVkZVVuY29udHJvbGxlZDogdHJ1ZSB9KS50aGVuKChsaXN0KSA9PiB7CiAgICAgIGZvciAoY29uc3QgY2xpZW50IG9mIGxpc3QpIHsKICAgICAgICBpZiAoY2xpZW50LnVybC5zdGFydHNXaXRoKHNlbGYubG9jYXRpb24ub3JpZ2luKSAmJiAiZm9jdXMiIGluIGNsaWVudCkgewogICAgICAgICAgcmV0dXJuIGNsaWVudC5uYXZpZ2F0ZSh1cmwpLnRoZW4oKG5hdmlnYXRlZCkgPT4gKG5hdmlnYXRlZCB8fCBjbGllbnQpLmZvY3VzKCkpOwogICAgICAgIH0KICAgICAgfQogICAgICByZXR1cm4gY2xpZW50cy5vcGVuV2luZG93KHVybCk7CiAgICB9KSwKICBdKSk7Cn0pOwo="}').items():
 target=dest/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(base64.b64decode(encoded))
print('REVIEWED UPDATE FILES PREPARED',3)
PYUPDATE
mkdir -p "$RUNTIME"
printf 'STAGE 2: production build, live service remains online\n'
# Install the exact lockfile, including the new jose dependency. No production data is mounted.
DEPS=/opt/power-home-staging/r934/source
cmp "$SOURCE/package-lock.json" "$DEPS/package-lock.json"
[[ -d "$DEPS/node_modules" ]]
# Exact lockfile match: reuse the existing verified dependency tree without another 1.2 GB install.
docker run --rm --network none -e NEXT_TELEMETRY_DISABLED=1 -v "$SOURCE:/app" -v "$DEPS/node_modules:/app/node_modules" -w /app node:22-bookworm-slim npm run build
cp -a "$SOURCE/.next/standalone/." "$RUNTIME/"
mkdir -p "$RUNTIME/public"
cp -a "$SOURCE/public/." "$RUNTIME/public/"
mkdir -p "$RUNTIME/.next"
cp -a "$SOURCE/.next/static" "$RUNTIME/.next/static"
[[ -f "$RUNTIME/server.js" ]]
cat > "$RUNTIME/Dockerfile" <<'DOCKER'
FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production HOSTNAME=0.0.0.0 PORT=3000 NEXT_TELEMETRY_DISABLED=1
COPY --chown=1001:1001 . .
USER 1001:1001
EXPOSE 3000
CMD ["node","server.js"]
DOCKER
docker build -t "$IMAGE" "$RUNTIME"
printf 'STAGE 3: isolated smoke test with disposable empty data\n'
docker run -d --name "$SMOKE" --network none -e AI_COACH_SCHEMA=1 -e APP_DATA_DIR=/tmp/power-home-smoke -e APP_SESSION_SECRET=disposable-r94291-smoke-secret -e APP_PASSWORD=disposable-r94291-smoke-password "$IMAGE"
for attempt in $(seq 1 30); do
  if docker exec "$SMOKE" node -e "fetch('http://127.0.0.1:3000/signup').then(async r=>{if(r.status!==200||!(await r.text()).includes('register-page'))process.exit(1)}).catch(()=>process.exit(1))"; then break; fi
  [[ $attempt != 30 ]]
  sleep 1
done
docker exec "$SMOKE" node -e "Promise.all(['/student','/api/packages','/privacy','/terms'].map(p=>fetch('http://127.0.0.1:3000'+p).then(r=>{if(!r.ok)throw Error('smoke')}))).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "if(!require('fs').readFileSync('/app/public/sw.js','utf8').includes('94.2.9.1'))process.exit(1)"
docker exec "$SMOKE" node -e "Promise.all(['/privacy','/terms'].map(async p=>{const r=await fetch('http://127.0.0.1:3000'+p);if(!r.ok||!(await r.text()).includes('arminsorkheii@gmail.com'))throw Error(p)})).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "Promise.all(['/api/student/power-os','/api/coach/readiness','/api/student/athlete-profile','/api/student/athlete-preferences','/api/student/muscle-history','/api/coach/memory','/api/coach/athlete-automations'].map(p=>fetch('http://127.0.0.1:3000'+p).then(r=>{if(r.status!==401)throw Error('auth smoke')}))).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "Promise.all(['/api/coach/ai-coach','/api/student/ai-consent','/api/exercise-videos/barbell-bench-press.mp4'].map(p=>fetch('http://127.0.0.1:3000'+p).then(r=>{if(r.status!==401)throw Error('auth')}))).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "fetch('http://127.0.0.1:3000/api/packages').then(async r=>{if(!r.ok)throw Error('schema initialization');const {DatabaseSync}=require('node:sqlite'),db=new DatabaseSync('/tmp/power-home-smoke/power-home.sqlite',{readOnly:true});for(const t of ['site_traffic_events','program_delivery_snapshots','coach_program_library'])if(!db.prepare('SELECT name FROM sqlite_master WHERE name=?').get(t))throw Error('missing '+t);const c=db.prepare('PRAGMA table_info(exercise_replacement_requests)').all().map(x=>x.name);for(const n of ['context_json','resolution_json'])if(!c.includes(n))throw Error('missing '+n)}).catch(()=>process.exit(1))"
docker exec "$SMOKE" ffmpeg -version >/dev/null
docker exec "$SMOKE" ffprobe -version >/dev/null
docker rm -f "$SMOKE"
printf 'STAGE 3b: verify all existing media and stage the two new reviewed clips\n'
fetch_release_blob e7efe6a0f2cc1043378a4ed997d9870c8b7352d8 "$STAGE/new-videos.tgz"
printf '%s  %s\n' "$MEDIA_SHA" "$STAGE/new-videos.tgz" | sha256sum -c -
mkdir -p "$STAGE/new-videos"
tar -xzf "$STAGE/new-videos.tgz" --strip-components=1 -C "$STAGE/new-videos"
python3 - "$SOURCE" "$TARGET" "$STAGE/new-videos" <<'PYMEDIA'
import pathlib,json,hashlib,sys
source,target,staged=map(pathlib.Path,sys.argv[1:]);records=json.loads((source/'docs/male-video-assets.json').read_text());assert len(records)==320
verified=json.loads(pathlib.Path("/opt/power-home-staging/r9411/direct-media/verified-assets.json").read_text());assert len(verified)==28
legacy={x["file"]:x["sha256"] for x in verified}
old=json.loads(pathlib.Path("/opt/power-home-staging/r9411/source/docs/direct-video-assets.json").read_text())
old_sources={x["file"]:x.get("sourceSha256") for x in old}
for record in records:
 name=record['file'];assert pathlib.PurePath(name).name==name
 local=target/'data/exercise-videos/male'/name
 candidate=staged/name
 if local.is_file():assert hashlib.sha256(local.read_bytes()).hexdigest() in (record['sha256'],legacy.get(name) if old_sources.get(name)==record.get('sourceSha256') else None),'Existing media hash mismatch: '+name
 if not candidate.is_file():candidate=local
 assert candidate.is_file(),'Missing required media: '+name
 assert hashlib.sha256(candidate.read_bytes()).hexdigest() in (record['sha256'],legacy.get(name) if old_sources.get(name)==record.get('sourceSha256') else None),'Media hash mismatch: '+name
print('ALL 320 LOCAL CLIPS VERIFIED; EXISTING MEDIA NOT MODIFIED')
PYMEDIA

printf 'STAGE 4: consistent data and configuration backup\n'
# Stop only for the final snapshot and application swap. Caddy stays running.
docker compose stop app
STOPPED=1
python3 - "$TARGET/data/power-home.sqlite" "$DEPLOY_BACKUP/before.sqlite" <<'PY'
import sqlite3,sys
source=sqlite3.connect(sys.argv[1]); target=sqlite3.connect(sys.argv[2]);source.backup(target)
assert target.execute('PRAGMA quick_check').fetchone()[0]=='ok'
target.close();source.close()
print('SQLITE BACKUP VERIFIED')
PY
tar -czf "$DEPLOY_BACKUP/data.tgz" -C "$TARGET" data
# Approved additive migration: validate on the consistent backup copy before touching live DB.
python3 - "$TARGET" "$SOURCE" "$DEPLOY_BACKUP" <<'PYAI'
import pathlib,sqlite3,sys,shutil,json,hashlib
app,source,backup=map(pathlib.Path,sys.argv[1:]);sql=(source/'migrations/ai-coach-up.sql').read_text()
shutil.copy2(backup/'before.sqlite',backup/'migration-test.sqlite')
for target in [backup/'migration-test.sqlite',app/'data/power-home.sqlite']:
 db=sqlite3.connect(target);db.executescript(sql);assert db.execute('PRAGMA quick_check').fetchone()[0]=='ok';db.close()
 print('AI ADDITIVE SCHEMA VERIFIED',target.name)
assert 'AI_COACH_SCHEMA: "1"' in (app/'compose.yaml').read_text()
print('ADDITIVE SCHEMA VERIFIED; EXISTING ROWS RETAINED')
PYAI

# Only copy new files after all source/asset checks and a consistent backup succeed.
python3 - "$STAGE/new-videos" "$TARGET/data/exercise-videos/male" <<'PYCOPY'
import pathlib,shutil,sys
source,target=map(pathlib.Path,sys.argv[1:]);target.mkdir(parents=True,exist_ok=True)
for item in source.glob('*.mp4'):
 dest=target/item.name
 if not dest.exists():shutil.copyfile(item,dest);dest.chmod(0o644)
print('NEW MEDIA ADDED WITHOUT OVERWRITING EXISTING FILES')
PYCOPY
tar --exclude=./data --exclude=./node_modules --exclude=./.next --exclude=./.sites-runtime --exclude='./runtime-*' -czf "$DEPLOY_BACKUP/source-before.tgz" -C "$TARGET" .
rsync -a --exclude=data --exclude=.env --exclude=node_modules --exclude=.next --exclude=.sites-runtime --exclude=Caddyfile --exclude=compose.yaml "$SOURCE/" "$TARGET/"
printf 'STAGE 5: activate release\n'
docker tag "$IMAGE" "$LIVE_IMAGE"
SWITCHED=1
docker compose up -d --no-build --force-recreate app
for attempt in $(seq 1 30); do
  if docker compose exec -T --interactive=false app node -e "fetch('http://127.0.0.1:3000/signup').then(async r=>{if(!r.ok||!(await r.text()).includes('register-page'))process.exit(1)}).catch(()=>process.exit(1))"; then break; fi
  [[ $attempt != 30 ]]
  sleep 1
done
python3 - "$DEPLOY_BACKUP/before.sqlite" "$TARGET/data/power-home.sqlite" <<'PY'
import sqlite3,sys
old=sqlite3.connect(sys.argv[1]);new=sqlite3.connect(sys.argv[2])
for table in ['coach_program_library','program_delivery_snapshots','site_traffic_events','ai_credentials','ai_settings','ai_consents','ai_consent_events','ai_jobs','ai_drafts','ai_draft_versions','ai_golden_rules','ai_systems','student_accounts','coach_states','applications','billing_records','billing_events','application_uploads','google_oauth_settings','google_login_preferences','chat_messages','exercise_replacement_requests','workout_sessions','life_files','student_life_items','student_daily_logs','student_day_settings','athlete_body_logs','athlete_preferences','coach_athlete_automations','movement_voice_feedback','video_annotations','workout_sets','weekly_reports','weekly_report_photos']:
    cols=[r[1] for r in old.execute('PRAGMA table_info('+table+')')]
    keys=[r[1] for r in old.execute('PRAGMA table_info('+table+')') if r[5]]
    if not cols: continue
    columns=','.join('"'+c+'"' for c in cols)
    where=' AND '.join('"'+k+'"=?' for k in keys)
    for row in old.execute('SELECT '+columns+' FROM '+table):
        found=new.execute('SELECT '+columns+' FROM '+table+' WHERE '+where,[row[cols.index(k)] for k in keys]).fetchone()
        assert found==row, 'existing row changed: '+table
    print('PRESERVED',table)
assert new.execute('PRAGMA quick_check').fetchone()[0]=='ok'
print('DATA INTEGRITY VERIFIED')
PY
curl -fLsS --connect-timeout 10 --max-time 30 https://arminsorkhei.ir/sw.js -o "$STAGE/live-sw.js"
grep -q '94.2.9.1' "$STAGE/live-sw.js"
curl -fLsS --connect-timeout 10 --max-time 30 https://arminsorkhei.ir/signup -o "$STAGE/live-signup.html"
grep -q 'register-page' "$STAGE/live-signup.html"
for page in privacy terms; do
  curl -4 --http1.1 -fLsS --connect-timeout 10 --max-time 30 "https://arminsorkhei.ir/$page" -o "$STAGE/live-$page.html"
  grep -q 'arminsorkheii@gmail.com' "$STAGE/live-$page.html"
done
docker compose exec -T --interactive=false app ffmpeg -version >/dev/null
docker compose exec -T --interactive=false app node -e "if(process.env.APP_ORIGIN!=='https://arminsorkhei.ir')throw Error('APP_ORIGIN mismatch')"
docker compose ps
printf '94.2.9.1\n' > "$STAGE/installed.ok"
printf 'INSTALL SUCCESS 94.2.9.1\nBACKUP: %s\n' "$DEPLOY_BACKUP"

