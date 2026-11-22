#!/usr/bin/env bash
# Power Home Coach 94.0.1: staged build, isolated smoke test, backup and rollback.
set -Eeuo pipefail
umask 077
TARGET=/opt/power-home-coach
STAGE=/opt/power-home-staging/r9401
SOURCE="$STAGE/source"
RUNTIME="$STAGE/runtime"
ARCHIVE_SHA=4aeb1086ca1e8c0aa9e5a2058a27fd14e9281207a7fe8df2ff72f2bdf0ac66db
IMAGE=power-home-coach-app:r9401
LIVE_IMAGE=power-home-coach-app:latest
ROLLBACK_IMAGE=power-home-coach-app:rollback-r9401-20261122
SMOKE=power-home-r9401-smoke
[[ $EUID == 0 && -d "$TARGET/data" && -f "$TARGET/compose.yaml" && -f "$TARGET/.env" ]]
# Refuse to overwrite a different deployed baseline.
curl -fLsS --max-time 30 https://arminsorkhei.ir/sw.js | grep -q '94.0.0' || { echo 'BASELINE MISMATCH: expected 94.0.0'; exit 1; }
[[ $(df -Pk /opt | awk 'NR==2 {print $4}') -gt 1800000 ]] || { echo 'Need 1.8 GB free staging space'; exit 1; }
mkdir -p "$STAGE" /opt/power-home-backups
exec > >(tee -a "$STAGE/install.log") 2>&1
cd "$TARGET"
[[ ! -f "$STAGE/installed.ok" ]] || { echo 'ALREADY INSTALLED'; exit 0; }
DEPLOY_BACKUP=$(mktemp -d /opt/power-home-backups/r9401-20261122-XXXXXX)
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
curl -4 --http1.1 -fL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 180 https://github.com/arminsorkheii-spec/power-home-coach/raw/refs/heads/main/power-home-94.0.1.tar.gz -o "$STAGE/source.tgz"
printf '%s  %s\n' "$ARCHIVE_SHA" "$STAGE/source.tgz" | sha256sum -c -
mkdir -p "$SOURCE" "$RUNTIME"
tar -xzf "$STAGE/source.tgz" -C "$SOURCE"
printf 'STAGE 1B: verified male-only video assets\n'
mkdir -p "$STAGE/assets"
curl -4 --http1.1 -fL --retry 3 --connect-timeout 20 --max-time 240 https://github.com/arminsorkheii-spec/power-home-coach/raw/refs/heads/main/power-home-male-videos-1.tar.gz -o "$STAGE/power-home-male-videos-1.tar.gz"
printf '%s  %s\n' '5540af5a87cbd84215470eaedf1d44661a92b4db04f79d14b35244f33c4c9609' "$STAGE/power-home-male-videos-1.tar.gz" | sha256sum -c -
curl -4 --http1.1 -fL --retry 3 --connect-timeout 20 --max-time 240 https://github.com/arminsorkheii-spec/power-home-coach/raw/refs/heads/main/power-home-male-videos-2.tar.gz -o "$STAGE/power-home-male-videos-2.tar.gz"
printf '%s  %s\n' '2edab2ae889efd8f0f10a915d016865c28f09a4d00bd5bbf30de392067a512b0' "$STAGE/power-home-male-videos-2.tar.gz" | sha256sum -c -
curl -4 --http1.1 -fL --retry 3 --connect-timeout 20 --max-time 240 https://github.com/arminsorkheii-spec/power-home-coach/raw/refs/heads/main/power-home-male-videos-3.tar.gz -o "$STAGE/power-home-male-videos-3.tar.gz"
printf '%s  %s\n' 'fb0d0b7dfe91291e2a899932d15d7e4596783f1b4b2ffb0f86ebb9ff4374b15e' "$STAGE/power-home-male-videos-3.tar.gz" | sha256sum -c -
python3 - "$STAGE" "$SOURCE/docs/male-video-assets.json" <<'PYASSETS'
import sys,tarfile,json,hashlib,pathlib
stage=pathlib.Path(sys.argv[1]); records=json.loads(pathlib.Path(sys.argv[2]).read_text()); allowed={r['file']:r for r in records}
assert len(allowed)==290
for pack in sorted(stage.glob('power-home-male-videos-*.tar.gz')):
 with tarfile.open(pack) as archive:
  for entry in archive:
   assert entry.isfile() and entry.name in allowed, 'Unexpected asset'
   data=archive.extractfile(entry).read(); record=allowed[entry.name]
   assert len(data)==record['bytes'] and hashlib.sha256(data).hexdigest()==record['sha256']
   (stage/'assets'/entry.name).write_bytes(data)
assert len(list((stage/'assets').glob('*.mp4')))==290
print('ALL 290 MALE VIDEO HASHES VERIFIED')
PYASSETS
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
docker run -d --name "$SMOKE" --network none -e APP_DATA_DIR=/tmp/power-home-smoke -e APP_SESSION_SECRET=disposable-r9401-smoke-secret -e APP_PASSWORD=disposable-r9401-smoke-password "$IMAGE"
for attempt in $(seq 1 30); do
  if docker exec "$SMOKE" node -e "fetch('http://127.0.0.1:3000/signup').then(async r=>{if(r.status!==200||!(await r.text()).includes('register-page'))process.exit(1)}).catch(()=>process.exit(1))"; then break; fi
  [[ $attempt != 30 ]]
  sleep 1
done
docker exec "$SMOKE" node -e "Promise.all(['/student','/api/packages','/privacy','/terms'].map(p=>fetch('http://127.0.0.1:3000'+p).then(r=>{if(!r.ok)throw Error('smoke')}))).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "if(!require('fs').readFileSync('/app/public/sw.js','utf8').includes('94.0.1'))process.exit(1)"
docker exec "$SMOKE" node -e "Promise.all(['/privacy','/terms'].map(async p=>{const r=await fetch('http://127.0.0.1:3000'+p);if(!r.ok||!(await r.text()).includes('arminsorkheii@gmail.com'))throw Error(p)})).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "Promise.all(['/api/student/power-os','/api/coach/readiness','/api/student/athlete-profile','/api/student/athlete-preferences','/api/student/muscle-history','/api/coach/memory','/api/coach/athlete-automations'].map(p=>fetch('http://127.0.0.1:3000'+p).then(r=>{if(r.status!==401)throw Error('auth smoke')}))).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "fetch('http://127.0.0.1:3000/api/exercise-videos/barbell-bench-press.mp4').then(r=>{if(r.status!==401)process.exit(1)}).catch(()=>process.exit(1))"
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
# Add only verified public exercise assets; preserve all existing user data.
install -d -m 0755 -o 1001 -g 1001 "$TARGET/data/exercise-videos" "$TARGET/data/exercise-videos/male"
for clip in "$STAGE/assets/"*.mp4; do install -m 0644 -o 1001 -g 1001 "$clip" "$TARGET/data/exercise-videos/male/"; done
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
for table in ['student_accounts','coach_states','applications','billing_records','billing_events','application_uploads','google_oauth_settings','google_login_preferences','chat_messages','exercise_replacement_requests','workout_sessions','life_files','student_life_items','student_daily_logs','student_day_settings','athlete_body_logs','athlete_preferences','coach_athlete_automations','movement_voice_feedback','video_annotations','workout_sets','weekly_reports','weekly_report_photos']:
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
grep -q '94.0.1' "$STAGE/live-sw.js"
curl -fLsS --connect-timeout 10 --max-time 30 https://arminsorkhei.ir/signup -o "$STAGE/live-signup.html"
grep -q 'register-page' "$STAGE/live-signup.html"
for page in privacy terms; do
  curl -4 --http1.1 -fLsS --connect-timeout 10 --max-time 30 "https://arminsorkhei.ir/$page" -o "$STAGE/live-$page.html"
  grep -q 'arminsorkheii@gmail.com' "$STAGE/live-$page.html"
done
docker compose exec -T --interactive=false app ffmpeg -version >/dev/null
docker compose exec -T --interactive=false app node -e "if(process.env.APP_ORIGIN!=='https://arminsorkhei.ir')throw Error('APP_ORIGIN mismatch')"
docker compose ps
printf '94.0.1\n' > "$STAGE/installed.ok"
printf 'INSTALL SUCCESS 94.0.1\nBACKUP: %s\n' "$DEPLOY_BACKUP"

