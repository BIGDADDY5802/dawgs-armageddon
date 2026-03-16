#!/bin/bash
# São Paulo (Liberdade) user_data.sh — Lab 3A
# Region: sa-east-1
# Role: Stateless compute only — NO local DB, NO PHI at rest
# All reads/writes go to Tokyo RDS over TGW
#
# Critical: SSM parameters and Secrets Manager live in Tokyo (ap-northeast-1).
# This EC2 runs in sa-east-1 but all AWS service calls for config/secrets
# explicitly target ap-northeast-1. The EC2 IAM role must allow cross-region
# SSM and Secrets Manager reads to Tokyo.

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

# This instance runs in São Paulo but reads config from Tokyo.
# Local region = where this EC2 lives (for CloudWatch logs).
# Tokyo region = where SSM, Secrets Manager, and RDS live.
LOCAL_REGION = "sa-east-1"
TOKYO_REGION = "ap-northeast-1"

LOG_GROUP        = "/aws/ec2/liberdade-app"
METRIC_NAMESPACE = "Lab/RDSApp"

# SSM and Secrets Manager calls go to Tokyo explicitly
SSM_ENDPOINT = "/lab/tokyo/db/endpoint"
SSM_PORT     = "/lab/tokyo/db/port"
SSM_NAME     = "/lab/tokyo/db/name"
SECRET_ID    = "shinjuku/rds/mysql"

# AWS clients: logs/metrics stay local, config/secrets go to Tokyo
ssm = boto3.client("ssm",            region_name=TOKYO_REGION)
sm  = boto3.client("secretsmanager", region_name=TOKYO_REGION)
cw  = boto3.client("cloudwatch",     region_name=LOCAL_REGION)

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
try:
    cw_handler = CloudWatchLogHandler(
        log_group=LOG_GROUP,
        stream_name="sp-app-stream",
        boto3_client=boto3.client("logs", region_name=LOCAL_REGION)
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
    """
    Reads DB config from Tokyo SSM and Secrets Manager.
    The EC2 is in sa-east-1 but these clients point to ap-northeast-1.
    Network path: EC2 → NAT/IGW → AWS API endpoint for ap-northeast-1.
    The RDS host returned here is a private IP in Tokyo — reachable via TGW.
    """
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
    # This TCP connection goes: São Paulo EC2 → TGW → Tokyo VPC → Tokyo RDS
    return pymysql.connect(
        host=c['host'], user=c['user'], password=c['password'],
        port=c['port'], database=c['dbname'], autocommit=True,
        connect_timeout=10  # TGW adds latency vs same-VPC — allow extra time
    )

@app.route("/health")
def health():
    return {"status": "ok", "region": LOCAL_REGION, "role": "stateless-compute"}, 200

@app.route("/")
def home():
    return """
    <h1>Lab 3A: São Paulo (Liberdade) — Stateless Compute</h1>
    <p>Region: sa-east-1 | Role: Compute only — reads/writes go to Tokyo RDS via TGW</p>
    <p><strong>No database exists in this region. This is by design (APPI).</strong></p>
    <ul>
        <li><a href='/add?text=SaoPauloEntry'>1. Add Note (writes to Tokyo)</a></li>
        <li><a href='/api/list'>2. List Notes (reads from Tokyo)</a></li>
        <li><a href='/api/public-feed'>3. Public Feed</a></li>
        <li><a href='/verify'>4. Verify TGW connectivity</a></li>
    </ul>
    """

@app.route("/add")
def add_note():
    note_text = request.args.get('text', 'São Paulo Entry')
    try:
        conn = get_conn()
        cur  = conn.cursor()
        cur.execute(
            "INSERT INTO notes (note, origin_region) VALUES (%s, %s)",
            (note_text, LOCAL_REGION)
        )
        cur.close()
        conn.close()
        return (
            f"Added: '{note_text}' — written to Tokyo RDS via TGW from {LOCAL_REGION} | "
            f"<a href='/api/list'>View All Notes</a>"
        )
    except Exception as e:
        record_failure(str(e))
        return f"Add Failed: {e}", 500

@app.route("/api/list")
def list_notes():
    """
    Reads from Tokyo RDS. All records — regardless of which region wrote them —
    appear here because there is one DB and it lives in Tokyo.
    This proves the single-source-of-truth architecture.
    """
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
        return (
            f"<h3>All Notes (stored in Tokyo ap-northeast-1):</h3>"
            f"<ul>{items}</ul>"
            f"<p><em>Served by São Paulo sa-east-1 via TGW</em></p>"
            f"<a href='/'>Back</a>"
        )
    except Exception as e:
        record_failure(str(e))
        return f"List Failed: {e}", 500

@app.route("/api/public-feed")
def public_feed():
    data = {
        "server_time_utc": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "serving_region":  LOCAL_REGION,
        "data_region":     TOKYO_REGION,
        "role":            "stateless-compute",
        "message":         "Liberdade — compute here, PHI in Tokyo. Cached by CloudFront 30s."
    }
    response = make_response(jsonify(data))
    response.headers["Cache-Control"] = "public, s-maxage=30, max-age=0"
    return response

@app.route("/verify")
def verify_tgw():
    """
    Lab 3A verification endpoint.
    Attempts a live DB connection to Tokyo over TGW and reports result.
    Use this to confirm the corridor is working after deployment.
    """
    try:
        conn = get_conn()
        cur  = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM notes;")
        count = cur.fetchone()[0]
        cur.execute("SELECT @@hostname, @@version;")
        db_info = cur.fetchone()
        cur.close()
        conn.close()
        c = get_config()
        return jsonify({
            "status":          "connected",
            "compute_region":  LOCAL_REGION,
            "db_region":       TOKYO_REGION,
            "db_host":         c['host'],
            "db_hostname":     db_info[0],
            "db_version":      db_info[1],
            "total_notes":     count,
            "corridor":        "TGW — São Paulo → Tokyo"
        })
    except Exception as e:
        record_failure(str(e))
        return jsonify({
            "status":  "failed",
            "error":   str(e),
            "hint":    "Check TGW peering, route tables, and RDS SG rule for São Paulo CIDR"
        }), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
PY

# 4. Systemd Service
cat >/etc/systemd/system/rdsapp.service <<'SERVICE'
[Unit]
Description=Lab 3A São Paulo App (Liberdade) — Stateless Compute
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/rdsapp
ExecStartPre=/usr/bin/sleep 20
ExecStart=/usr/bin/python3 /opt/rdsapp/app.py
Restart=always
RestartSec=10s
Environment=AWS_REGION=sa-east-1

[Install]
WantedBy=multi-user.target
SERVICE

# 5. Start
systemctl daemon-reload
systemctl enable rdsapp
systemctl start rdsapp
