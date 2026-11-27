#!/usr/bin/env bash
# Power Home Coach 94.2.6: staged build, isolated smoke test, backup and rollback.
set -Eeuo pipefail
umask 077
TARGET=/opt/power-home-coach
STAGE=/opt/power-home-staging/r9426
SOURCE="$STAGE/source"
RUNTIME="$STAGE/runtime"
ARCHIVE_SHA=7cd584b65a2c8a6c9facbf77bef4db5f122dd3a84404f443148aee35e6080721
IMAGE=power-home-coach-app:r9426
LIVE_IMAGE=power-home-coach-app:latest
ROLLBACK_IMAGE=power-home-coach-app:rollback-r9426-20261127
SMOKE=power-home-r9426-smoke
CODE_COMMIT=${1:?Supply the GitHub commit containing the reviewed release parts}
[[ $CODE_COMMIT =~ ^[a-f0-9]{40}$ ]] || { echo 'A pinned40-character commit is required'; exit 1; }
RELEASE_URL="https://raw.githubusercontent.com/arminsorkheii-spec/power-home-coach/$CODE_COMMIT"
MEDIA_SHA=378780658669793247fc6835196380c2746226d6246a86c112dec3f9c359f136
[[ $EUID == 0 && -d "$TARGET/data" && -f "$TARGET/compose.yaml" && -f "$TARGET/.env" ]]
curl -fLsS --max-time 30 https://arminsorkhei.ir/sw.js | grep -q '94.1.2' || { echo 'BASELINE MISMATCH: expected94.1.2'; exit 1; }
[[ $(df -Pk /opt | awk 'NR==2 {print $4}') -gt 2000000 ]] || { echo 'Need2GB free staging space'; exit 1; }
mkdir -p "$STAGE" /opt/power-home-backups
exec > >(tee -a "$STAGE/install.log") 2>&1
cd "$TARGET"
[[ ! -f "$STAGE/installed.ok" ]] || { echo 'ALREADY INSTALLED'; exit 0; }
DEPLOY_BACKUP=$(mktemp -d /opt/power-home-backups/r9426-20261127-XXXXXX)
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
printf 'STAGE 1: verified release download\n'
for part in 01 02; do
  curl -4 --http1.1 -fL --retry 2 --connect-timeout 20 --max-time 180 "$RELEASE_URL/power-home-94.2.6.part-$part" -o "$STAGE/source.part-$part"
done
cat "$STAGE/source.part-01" "$STAGE/source.part-02" > "$STAGE/source.tgz"
printf '%s  %s\n' "$ARCHIVE_SHA" "$STAGE/source.tgz" | sha256sum -c -
mkdir -p "$SOURCE" "$RUNTIME"
tar -xzf "$STAGE/source.tgz" -C "$SOURCE"
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
docker run -d --name "$SMOKE" --network none -e AI_COACH_SCHEMA=1 -e APP_DATA_DIR=/tmp/power-home-smoke -e APP_SESSION_SECRET=disposable-r9426-smoke-secret -e APP_PASSWORD=disposable-r9426-smoke-password "$IMAGE"
for attempt in $(seq 1 30); do
  if docker exec "$SMOKE" node -e "fetch('http://127.0.0.1:3000/signup').then(async r=>{if(r.status!==200||!(await r.text()).includes('register-page'))process.exit(1)}).catch(()=>process.exit(1))"; then break; fi
  [[ $attempt != 30 ]]
  sleep 1
done
docker exec "$SMOKE" node -e "Promise.all(['/student','/api/packages','/privacy','/terms'].map(p=>fetch('http://127.0.0.1:3000'+p).then(r=>{if(!r.ok)throw Error('smoke')}))).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "if(!require('fs').readFileSync('/app/public/sw.js','utf8').includes('94.2.6'))process.exit(1)"
docker exec "$SMOKE" node -e "Promise.all(['/privacy','/terms'].map(async p=>{const r=await fetch('http://127.0.0.1:3000'+p);if(!r.ok||!(await r.text()).includes('arminsorkheii@gmail.com'))throw Error(p)})).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "Promise.all(['/api/student/power-os','/api/coach/readiness','/api/student/athlete-profile','/api/student/athlete-preferences','/api/student/muscle-history','/api/coach/memory','/api/coach/athlete-automations'].map(p=>fetch('http://127.0.0.1:3000'+p).then(r=>{if(r.status!==401)throw Error('auth smoke')}))).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "Promise.all(['/api/coach/ai-coach','/api/student/ai-consent','/api/exercise-videos/barbell-bench-press.mp4'].map(p=>fetch('http://127.0.0.1:3000'+p).then(r=>{if(r.status!==401)throw Error('auth')}))).catch(()=>process.exit(1))"
docker exec "$SMOKE" node -e "fetch('http://127.0.0.1:3000/api/packages').then(async r=>{if(!r.ok)throw Error('schema initialization');const {DatabaseSync}=require('node:sqlite'),db=new DatabaseSync('/tmp/power-home-smoke/power-home.sqlite',{readOnly:true});for(const t of ['site_traffic_events','program_delivery_snapshots'])if(!db.prepare('SELECT name FROM sqlite_master WHERE name=?').get(t))throw Error('missing '+t);const c=db.prepare('PRAGMA table_info(exercise_replacement_requests)').all().map(x=>x.name);for(const n of ['context_json','resolution_json'])if(!c.includes(n))throw Error('missing '+n)}).catch(()=>process.exit(1))"
docker exec "$SMOKE" ffmpeg -version >/dev/null
docker exec "$SMOKE" ffprobe -version >/dev/null
docker rm -f "$SMOKE"
printf 'STAGE 3b: verify all existing media and stage the two new reviewed clips\n'
curl -4 --http1.1 -fL --retry 2 --connect-timeout 20 --max-time 180 "$RELEASE_URL/power-home-94.2.6-new-videos.tar.gz" -o "$STAGE/new-videos.tgz"
printf '%s  %s\n' "$MEDIA_SHA" "$STAGE/new-videos.tgz" | sha256sum -c -
mkdir -p "$STAGE/new-videos"
tar -xzf "$STAGE/new-videos.tgz" --strip-components=1 -C "$STAGE/new-videos"
python3 - "$SOURCE" "$TARGET" "$STAGE/new-videos" <<'PYMEDIA'
import pathlib,json,hashlib,sys
source,target,staged=map(pathlib.Path,sys.argv[1:]);records=json.loads((source/'docs/male-video-assets.json').read_text());assert len(records)==320
for record in records:
 name=record['file'];assert pathlib.PurePath(name).name==name
 local=target/'data/exercise-videos/male'/name
 candidate=staged/name
 if local.is_file():assert hashlib.sha256(local.read_bytes()).hexdigest()==record['sha256'],'Existing media hash mismatch: '+name
 if not candidate.is_file():candidate=local
 assert candidate.is_file(),'Missing required media: '+name
 assert hashlib.sha256(candidate.read_bytes()).hexdigest()==record['sha256'],'Media hash mismatch: '+name
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
for table in ['ai_credentials','ai_settings','ai_consents','ai_consent_events','ai_jobs','ai_drafts','ai_draft_versions','ai_golden_rules','ai_systems','student_accounts','coach_states','applications','billing_records','billing_events','application_uploads','google_oauth_settings','google_login_preferences','chat_messages','exercise_replacement_requests','workout_sessions','life_files','student_life_items','student_daily_logs','student_day_settings','athlete_body_logs','athlete_preferences','coach_athlete_automations','movement_voice_feedback','video_annotations','workout_sets','weekly_reports','weekly_report_photos']:
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
grep -q '94.2.6' "$STAGE/live-sw.js"
curl -fLsS --connect-timeout 10 --max-time 30 https://arminsorkhei.ir/signup -o "$STAGE/live-signup.html"
grep -q 'register-page' "$STAGE/live-signup.html"
for page in privacy terms; do
  curl -4 --http1.1 -fLsS --connect-timeout 10 --max-time 30 "https://arminsorkhei.ir/$page" -o "$STAGE/live-$page.html"
  grep -q 'arminsorkheii@gmail.com' "$STAGE/live-$page.html"
done
docker compose exec -T --interactive=false app ffmpeg -version >/dev/null
docker compose exec -T --interactive=false app node -e "if(process.env.APP_ORIGIN!=='https://arminsorkhei.ir')throw Error('APP_ORIGIN mismatch')"
docker compose ps
printf '94.2.6\n' > "$STAGE/installed.ok"
printf 'INSTALL SUCCESS 94.2.6\nBACKUP: %s\n' "$DEPLOY_BACKUP"

