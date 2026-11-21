#!/usr/bin/env bash
# Power Home Coach 93.8.5: staged build, isolated smoke test, backup and rollback.
set -Eeuo pipefail
umask 077
TARGET=/opt/power-home-coach
STAGE=/opt/power-home-staging/r9385
SOURCE="$STAGE/source"
RUNTIME="$STAGE/runtime"
ARCHIVE_SHA=e4710f373ea29fa8c404df7e84b11113a8d54c3a222ba0572345f2e77df7d14b
IMAGE=power-home-coach-app:r9385
LIVE_IMAGE=power-home-coach-app:latest
ROLLBACK_IMAGE=power-home-coach-app:rollback-r9385-20261121
SMOKE=power-home-r9385-smoke
[[ $EUID == 0 && -d "$TARGET/data" && -f "$TARGET/compose.yaml" && -f "$TARGET/.env" ]]
mkdir -p "$STAGE" /opt/power-home-backups
exec > >(tee -a "$STAGE/install.log") 2>&1
cd "$TARGET"
[[ ! -f "$STAGE/installed.ok" ]] || { echo 'ALREADY INSTALLED'; exit 0; }
DEPLOY_BACKUP=$(mktemp -d /opt/power-home-backups/r9385-20261121-XXXXXX)
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
  if [[ $SWITCHED == 1 ]]; then docker tag "$ROLLBACK_IMAGE" "$LIVE_IMAGE"; docker compose up -d --no-build --force-recreate app || true
  elif [[ $STOPPED == 1 ]]; then docker compose start app || true
  fi
  echo "BACKUP: $DEPLOY_BACKUP"
  exit "$code"
}
trap on_error ERR
printf 'STAGE 1: verified release download\n'
curl -4 --http1.1 -fL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 180 https://github.com/arminsorkheii-spec/power-home-coach/raw/e9a382c4128343857862c10e5cf568d4423df69c/power-home-93.8.2.tar.gz -o "$STAGE/source.tgz"
printf '%s  %s\n' "$ARCHIVE_SHA" "$STAGE/source.tgz" | sha256sum -c -
mkdir -p "$SOURCE" "$RUNTIME"
tar -xzf "$STAGE/source.tgz" -C "$SOURCE"
(cd "$SOURCE" && python3 - <<'PATCH9383'
from pathlib import Path
p=Path('components/coach-applications.tsx');s=p.read_text();s=s.replace('import { PackageChoices }','import { PowerGraphicIcon } from "@/components/power-graphic-icon";\nimport { PackageChoices }',1)
s=s.replace('<h1><ClipboardList />','<h1><PowerGraphicIcon name="orders" size={46} />')
s=s.replace('key={item.key} onClick={() => setFilter(item.key)} className=', 'key={item.key} data-request-tone={item.key} aria-pressed={filter === item.key} onClick={() => setFilter(item.key)} className=')
s=s.replace('key={item.key} className={filter === item.key', 'key={item.key} data-request-tone={item.key} aria-pressed={filter === item.key} className={filter === item.key')
s=s.replace('<span className={`request-status status-${application.status}`}>','<span data-status={application.status} className={`request-status request-status-badge status-${application.status}`}><i aria-hidden="true" />')
s=s.replace('key={step.key} disabled={busy', 'key={step.key} data-status={step.key} disabled={busy')
p.write_text(s)
p=Path('app/globals.css');s=p.read_text().replace('filter:grayscale(1)','filter:none');s+='''
/* 93.8.5: semantic accents on the actual requests board, independent of neutral surfaces. */
.request-board [data-request-tone]{--request-status-rgb:171,186,216}
.request-board [data-request-tone=new]{--request-status-rgb:133,194,238}
.request-board [data-request-tone=payment]{--request-status-rgb:134,211,214}
.request-board [data-request-tone=writing]{--request-status-rgb:195,167,241}
.request-board [data-request-tone=ready]{--request-status-rgb:112,216,158}
.request-board .request-stats button,.request-board .request-filters button{border-color:rgba(var(--request-status-rgb),.4)!important;background:rgba(var(--request-status-rgb),.08)!important;color:rgb(var(--request-status-rgb))!important}
.request-board .request-stats small{color:inherit!important}
.request-board .request-stats strong{color:inherit!important}
.request-board .request-stats button.active,.request-board .request-filters button.active{border-color:rgb(var(--request-status-rgb))!important;background:rgba(var(--request-status-rgb),.22)!important;box-shadow:inset 0 0 0 1px rgba(var(--request-status-rgb),.25)}
.request-board .request-status-badge{max-width:100%;width:fit-content;white-space:normal;font-size:11px}
.request-board-head h1 .power-graphic-icon{width:46px;height:46px;flex-shrink:0}
html[data-theme=light] .request-board [data-request-tone]{--request-status-rgb:66,85,112}
html[data-theme=light] .request-board [data-request-tone=new]{--request-status-rgb:34,102,159}
html[data-theme=light] .request-board [data-request-tone=payment]{--request-status-rgb:24,110,117}
html[data-theme=light] .request-board [data-request-tone=writing]{--request-status-rgb:113,65,166}
html[data-theme=light] .request-board [data-request-tone=ready]{--request-status-rgb:24,115,66}
.request-board .request-timeline button.done{color:#bddbcf}
.request-board .request-timeline button.done i{background:#70d89e;color:#10291c}
html[data-theme=light] .request-board .request-timeline button.done{color:#187342}
''';p.write_text(s)
for f in ['lib/pwa-client.ts','public/sw.js']:
 p=Path('.')/f;p.write_text(p.read_text().replace('93.8.2','93.8.5'))

PATCH9383
)
curl -4 -fL --retry 3 --max-time 90 https://github.com/arminsorkheii-spec/power-home-coach/raw/refs/heads/main/power-home-9385-delta.tar.gz -o "$STAGE/delta.tgz"
printf '%s  %s\n' 'c3301b6ba199e21751f3b219c2417312f2a5f23152454ba6b93ab4fccd533906' "$STAGE/delta.tgz" | sha256sum -c -
tar -xzf "$STAGE/delta.tgz" -C "$SOURCE"
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
docker run -d --name "$SMOKE" --network none -e APP_DATA_DIR=/tmp/power-home-smoke -e APP_SESSION_SECRET=disposable-r9385-smoke-secret -e APP_PASSWORD=disposable-r9385-smoke-password "$IMAGE"
for attempt in $(seq 1 30); do
  if docker exec "$SMOKE" node -e "fetch('http://127.0.0.1:3000/signup').then(async r=>{if(r.status!==200||!(await r.text()).includes('register-page'))process.exit(1)}).catch(()=>process.exit(1))"; then break; fi
  [[ $attempt != 30 ]]
  sleep 1
done
docker exec "$SMOKE" node -e "Promise.all(['/student','/api/packages','/privacy','/terms'].map(p=>fetch('http://127.0.0.1:3000'+p).then(r=>{if(!r.ok)throw Error('smoke')}))).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "if(!require('fs').readFileSync('/app/public/sw.js','utf8').includes('93.8.5'))process.exit(1)"
docker exec "$SMOKE" node -e "Promise.all(['/privacy','/terms'].map(async p=>{const r=await fetch('http://127.0.0.1:3000'+p);if(!r.ok||!(await r.text()).includes('arminsorkheii@gmail.com'))throw Error(p)})).catch(()=>process.exit(1))"
docker exec "$SMOKE" ffmpeg -version >/dev/null
docker exec "$SMOKE" ffprobe -version >/dev/null
docker rm -f "$SMOKE"
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
for table in ['student_accounts','coach_states','applications','billing_records','billing_events','application_uploads','google_oauth_settings','google_login_preferences','chat_messages','exercise_replacement_requests','workout_sessions','life_files']:
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
grep -q '93.8.5' "$STAGE/live-sw.js"
curl -fLsS --connect-timeout 10 --max-time 30 https://arminsorkhei.ir/signup -o "$STAGE/live-signup.html"
grep -q 'register-page' "$STAGE/live-signup.html"
for page in privacy terms; do
  curl -4 --http1.1 -fLsS --connect-timeout 10 --max-time 30 "https://arminsorkhei.ir/$page" -o "$STAGE/live-$page.html"
  grep -q 'arminsorkheii@gmail.com' "$STAGE/live-$page.html"
done
docker compose exec -T --interactive=false app ffmpeg -version >/dev/null
docker compose exec -T --interactive=false app node -e "if(process.env.APP_ORIGIN!=='https://arminsorkhei.ir')throw Error('APP_ORIGIN mismatch')"
docker compose ps
printf '93.8.5\n' > "$STAGE/installed.ok"
printf 'INSTALL SUCCESS 93.8.5\nBACKUP: %s\n' "$DEPLOY_BACKUP"

