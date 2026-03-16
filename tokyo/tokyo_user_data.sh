#!/bin/bash
# Tokyo (Shinjuku) user_data.sh — Lab 3A
# Region: ap-northeast-1
# Role: Data authority — RDS lives here, SSM/Secrets Manager here
# PHI compliance: APPI — patient data stored in Japan only

# 1. Install System Dependencies
dnf update -y
dnf install -y python3-pip mariadb105
pip3 install flask pymysql boto3 watchtower

# 2. Create Directory
mkdir -p /opt/rdsapp

# 3. Create the Python App
cat >/opt/rdsapp/app.py <<'PY'
import json
import os
import boto3
import pymysql
import logging
from flask import Flask, request, make_response, jsonify
from watchtower import CloudWatchLogHandler
import datetime
import hashlib

# Tokyo is the data authority — all AWS service calls go to ap-northeast-1
REGION = "ap-northeast-1"
LOG_GROUP = "/aws/ec2/shinjuku-rds-app"
METRIC_NAMESPACE = "Lab/RDSApp"

# SSM parameter paths (Tokyo-specific)
SSM_ENDPOINT = "/lab/tokyo/db/endpoint"
SSM_PORT     = "/lab/tokyo/db/port"
SSM_NAME     = "/lab/tokyo/db/name"
SECRET_ID    = "shinjuku/rds/mysql"

ssm = boto3.client("ssm", region_name=REGION)
sm  = boto3.client("secretsmanager", region_name=REGION)
cw  = boto3.client("cloudwatch", region_name=REGION)

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
try:
    cw_handler = CloudWatchLogHandler(
        log_group=LOG_GROUP,
        stream_name="app-stream",
        boto3_client=boto3.client("logs", region_name=REGION)
    )
    logger.addHandler(cw_handler)
except Exception as e:
    print(f"CloudWatch Logs Setup Pending: {e}")

app = Flask(__name__)

def record_failure(error_msg):
    logger.error(f"DB_CONNECTION_FAILURE: {error_msg}")
    try:
        cw.put_metric_data(
            Namespace=METRIC_NAMESPACE,
            MetricData=[{'MetricName': 'DBConnectionErrors', 'Value': 1.0, 'Unit': 'Count'}]
        )
    except Exception as e:
        logger.warning(f"Failed to push metric: {e}")

def get_config():
    try:
        p_resp = ssm.get_parameters(
            Names=[SSM_ENDPOINT, SSM_PORT, SSM_NAME],
            WithDecryption=False
        )
        p_map = {p['Name']: p['Value'] for p in p_resp['Parameters']}
        s_resp = sm.get_secret_value(SecretId=SECRET_ID)
        secret = json.loads(s_resp['SecretString'])
        return {
            'host':     p_map.get(SSM_ENDPOINT),
            'port':     int(p_map.get(SSM_PORT, 3306)),
            'dbname':   p_map.get(SSM_NAME, 'labdb'),
            'user':     secret.get('username'),
            'password': secret.get('password')
        }
    except Exception as e:
        record_failure(str(e))
        raise e

def get_conn():
    c = get_config()
    return pymysql.connect(
        host=c['host'], user=c['user'], password=c['password'],
        port=c['port'], database=c['dbname'], autocommit=True
    )

@app.route("/health")
def health():
    return {"status": "ok", "region": REGION, "role": "data-authority"}, 200

@app.route("/")
def home():
    return """
    <h1>Lab 3A: Tokyo (Shinjuku) — Data Authority</h1>
    <p>Region: ap-northeast-1 | Role: PHI storage (APPI compliant)</p>
    <ul>
        <li><a href='/init'>1. Init DB</a></li>
        <li><a href='/add?text=TokyoEntry'>2. Add Note (?text=...)</a></li>
        <li><a href='/api/list'>3. List Notes</a></li>
        <li><a href='/api/public-feed'>4. Public Feed (cached)</a></li>
    </ul>
    """

@app.route("/init")
def init_db():
    try:
        c = get_config()
        conn = pymysql.connect(
            host=c['host'], user=c['user'],
            password=c['password'], port=c['port']
        )
        cur = conn.cursor()
        cur.execute(f"CREATE DATABASE IF NOT EXISTS {c['dbname']};")
        cur.execute(f"USE {c['dbname']};")
        cur.execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id INT AUTO_INCREMENT PRIMARY KEY,
                note VARCHAR(255),
                origin_region VARCHAR(32) DEFAULT 'ap-northeast-1',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        cur.close()
        conn.close()
        return "Init Success — Tokyo DB ready. <a href='/'>Back</a>"
    except Exception as e:
        record_failure(str(e))
        return f"Init Failed: {e}", 500

@app.route("/add")
def add_note():
    note_text = request.args.get('text', 'Tokyo Entry')
    origin    = request.args.get('origin', 'ap-northeast-1')
    try:
        conn = get_conn()
        cur  = conn.cursor()
        cur.execute(
            "INSERT INTO notes (note, origin_region) VALUES (%s, %s)",
            (note_text, origin)
        )
        cur.close()
        conn.close()
        return f"Added: {note_text} from {origin} | <a href='/api/list'>View List</a>"
    except Exception as e:
        record_failure(str(e))
        return f"Add Failed: {e}", 500

@app.route("/api/list")
def list_notes():
    try:
        conn = get_conn()
        cur  = conn.cursor()
        cur.execute("SELECT id, note, origin_region, created_at FROM notes ORDER BY id DESC;")
        rows = cur.fetchall()
        cur.close()
        conn.close()
        items = "".join([
            f"<li>[{r[2]}] {r[1]} <small>({r[3]})</small></li>"
            for r in rows
        ])
        return f"<h3>Notes (all regions write here):</h3><ul>{items}</ul><a href='/'>Back</a>"
    except Exception as e:
        record_failure(str(e))
        return f"List Failed: {e}", 500

@app.route("/api/public-feed")
def public_feed():
    stable = {
        "serving_region": REGION,
        "role":           "data-authority",
        "message":        "Shinjuku — PHI stored here. Cached by CloudFront 30s."
    }
    stable_body = json.dumps(stable, sort_keys=True)
    etag = f'"{hashlib.md5(stable_body.encode()).hexdigest()}"'

    if request.headers.get("If-None-Match") == etag:
        return "", 304

    stable["server_time_utc"] = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    body = json.dumps(stable)

    response = make_response(body)
    response.headers["Content-Type"]    = "application/json"
    response.headers["Cache-Control"]   = "public, s-maxage=60, max-age=30"
    response.headers["ETag"]            = etag
    response.headers["Last-Modified"]   = "Sat, 14 Mar 2026 00:00:00 GMT"
    return response

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
PY

# 4. Systemd Service
cat >/etc/systemd/system/rdsapp.service <<'SERVICE'
[Unit]
Description=Lab 3A Tokyo RDS App (Shinjuku)
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/rdsapp
ExecStartPre=/usr/bin/sleep 20
ExecStart=/usr/bin/python3 /opt/rdsapp/app.py
Restart=always
RestartSec=10s
Environment=AWS_REGION=ap-northeast-1

[Install]
WantedBy=multi-user.target
SERVICE

# 5. Start
systemctl daemon-reload
systemctl enable rdsapp
systemctl start rdsapp
