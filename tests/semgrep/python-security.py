# Semgrep test target for semgrep-rules/python-security.yaml (run: pnpm test:semgrep).
#
# The first part is the OTTER-774 scanner fixture: deliberately insecure, never run it. Submitting
# this file as study code also checks the scanner end to end. The credentials are fake but
# format-shaped; secrets.r tests the rules that match them. The keys differ from r-security.r's on
# purpose, so a dedupe pass cannot merge the two files into one finding.
#
# The second part is ordinary research code that sits next to each pattern. Each "ok" line must not
# match, so a rule that starts to fire on legitimate analysis fails the test.

import asyncio
import hashlib
import logging
import os
import pickle
import pty
import random
import subprocess
import subprocess as sp
import sqlite3
import tarfile
import tempfile
import zipfile
from os import system

import pandas as pd
import requests
import yaml

# --- 1. Hardcoded credentials --------------------------------------------
# ruleid: py-hardcoded-password
AWS_ACCESS_KEY_ID = "AKIAI44QH8DHBEXAMPLE"
# ruleid: py-hardcoded-password
AWS_SECRET_ACCESS_KEY = "je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY"
# ruleid: py-hardcoded-password
GITHUB_TOKEN = "ghp_9F8E7D6C5B4A3210FEDCBA9876543210ABCD"
SLACK_WEBHOOK = "https://hooks.slack.com/services/T11111111/B11111111/YYYYYYYYYYYYYYYYYYYYYYYY"
STRIPE_KEY = "sk_live_51H8sT2KpQrStUvWxYz0123456789abcdef"
# ruleid: py-hardcoded-password
DB_PASSWORD = "correct-horse-battery-staple"

PRIVATE_KEY = """-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAy8Km4R7pLq3N5xT2vYcG8zKiO2dE5fH8tB1vW4jY0pQ3rXnF
-----END RSA PRIVATE KEY-----"""


# --- 2. Arbitrary code execution from untrusted input --------------------
def run_user_expr(user_input):
    # ruleid: py-eval-exec
    return eval(user_input)


def run_user_block(src):
    # ruleid: py-eval-exec
    exec(src)


def apply_user_fn(name, arg):
    # ruleid: py-dynamic-dispatch
    return globals()[name](arg)


# --- 3. Command injection ------------------------------------------------
def count_lines(filename):
    # ruleid: py-command-injection, py-shell-command
    return os.system("wc -l " + filename)


def archive_dir(d):
    # ruleid: py-subprocess-shell-injection, py-shell-command
    return subprocess.check_output(f"tar czf /tmp/out.tgz {d}", shell=True)


# --- 4. SQL injection ----------------------------------------------------
def find_user(con, uid):
    cur = con.cursor()
    # ruleid: py-sql-injection
    cur.execute("SELECT * FROM users WHERE id = '" + uid + "'")
    return cur.fetchall()


# --- 5. Insecure deserialization -----------------------------------------
def load_remote_model(url):
    # ruleid: py-remote-deserialization, py-tls-verification-disabled
    return pickle.loads(requests.get(url, verify=False).content)


def load_config(path):
    with open(path) as fh:
        # ruleid: py-unsafe-yaml-load
        return yaml.load(fh, Loader=yaml.UnsafeLoader)


# --- 6. TLS verification disabled ----------------------------------------
# ruleid: py-tls-verification-disabled
os.environ["PYTHONHTTPSVERIFY"] = "0"
# ruleid: py-tls-verification-disabled
os.environ["CURL_CA_BUNDLE"] = ""

SESSION = requests.Session()
# ruleid: py-tls-verification-disabled
SESSION.verify = False


def fetch(u):
    # ruleid: py-tls-verification-disabled
    return requests.get(u, verify=False, timeout=30)


# --- 7. Remote code download and execution -------------------------------
def bootstrap():
    # ruleid: py-remote-code-execution, py-tls-verification-disabled
    src = requests.get("http://packages.internal.example.com/bootstrap.py", verify=False).text
    exec(src)
    # ruleid: py-remote-code-execution, py-shell-command
    subprocess.call("curl -sk https://example.com/install.sh | bash", shell=True)


# --- 8. Weak cryptography and predictable randomness ---------------------
def hash_password(pw):
    # ruleid: py-weak-hash-for-secret
    return hashlib.md5(pw.encode()).hexdigest()


def weak_digest(blob):
    # ruleid: py-weak-hash
    return hashlib.sha1(blob).hexdigest()


random.seed(42)


def session_token():
    # ruleid: py-insecure-random-for-secret
    return "".join(random.choice("abcdefghijklmnopqrstuvwxyz") for _ in range(16))


# --- 9. Path traversal ---------------------------------------------------
def read_report(name):
    # ruleid: py-path-from-parameter
    with open(os.path.join("/srv/reports", name)) as fh:
        return fh.read()


# --- 10. Insecure temp files and permissions -----------------------------
def stash(rows):
    p = "/tmp/scratch.csv"
    with open(p, "w") as fh:
        fh.write("\n".join(rows))
    # ruleid: py-world-writable-permissions
    os.chmod(p, 0o777)
    return p


def scratch_path():
    # ruleid: py-insecure-mktemp
    return tempfile.mktemp(suffix=".csv")


# --- 11. Secrets written to logs -----------------------------------------
def connect():
    # ruleid: py-secret-in-log
    print("connecting with password:", DB_PASSWORD)
    with open("/tmp/debug.log", "a") as fh:
        # ruleid: py-secret-in-log
        fh.write(f"token: {GITHUB_TOKEN}\n")
    return sqlite3.connect(":memory:")


# --- 12. Silent failure --------------------------------------------------
def risky(f):
    # ruleid: py-silent-exception
    try:
        return f()
    except Exception:
        pass


# --- 13. Assert-based access control (stripped under -O) -----------------
def admin_only(user):
    # ruleid: py-assert-access-control
    assert user.get("is_admin"), "not an admin"
    return True


# --- 14. Unsafe archive extraction (path traversal via member names) -----
def unpack(tar_path, dest="/tmp/unpacked"):
    with tarfile.open(tar_path) as tf:
        # ruleid: py-tarfile-extractall
        tf.extractall(dest)


# --- 15. Binding to all interfaces with debug enabled --------------------
def serve(app):
    # ruleid: py-server-exposed
    app.run(host="0.0.0.0", port=8080, debug=True)


# --- 16. Other risky calls ----------------------------------------------
def legacy_transfer(host, user, pw, key, client, server):
    # ruleid: py-cleartext-protocol
    ftp = ftplib.FTP(host)
    # ruleid: py-cleartext-protocol
    session = telnetlib.Telnet(host)
    # ruleid: py-cleartext-protocol
    requests.get("http://api.example.org/v1", auth=(user, pw), timeout=30)
    # ruleid: py-ssh-unknown-host-accepted
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    # ruleid: py-weak-cipher
    des = Crypto.Cipher.DES.new(key, Crypto.Cipher.DES.MODE_CBC)
    # ruleid: py-weak-cipher
    ecb = Crypto.Cipher.AES.new(key, Crypto.Cipher.AES.MODE_ECB)
    # ruleid: py-subprocess-shell, py-shell-command
    subprocess.run("ls -la /data", shell=True)
    # ruleid: py-xml-parser
    tree = xml.etree.ElementTree.parse("upload.xml")
    # ruleid: py-local-deserialization
    model = pickle.load(open("model.pkl", "rb"))
    # ruleid: py-server-exposed
    server.bind(("0.0.0.0", 9000))


# --- 17. Near misses that still use the network ---------------------------
# Safe for the security rules, but a study must not make network calls at all, so
# privacy-py-network-call reports each of these. That is why they sit above the legitimate part.

# ok: py-remote-code-execution
readme = requests.get("https://example.org/readme.txt", timeout=30).text
print(len(readme))

# ok: py-tls-verification-disabled
resp = requests.get(api_url, verify="certs/ca.pem", timeout=30)

# ok: py-cleartext-protocol
ftp = ftplib.FTP_TLS("files.example.org")
# ok: py-cleartext-protocol
resp = requests.get("https://api.example.org/v1", auth=(user, secret), timeout=30)

# --- 17. External command launches --------------------------------------
# ruleid: py-shell-command
os.system(cmd)
# ruleid: py-shell-command
os.popen(cmd)
# ruleid: py-shell-command
subprocess.run(['sh', '-c', cmd])
# ruleid: py-shell-command
os.execvp(program, args)
# ruleid: py-shell-command
os.spawnv(mode, program, args)

# Ordinary command launches also need review under the catch-all rule.
# ruleid: py-shell-command
os.system("nvidia-smi")

# ruleid: py-shell-command
subprocess.run(["Rscript", "model.R"], check=True)

# Aliased and directly imported names resolve to the same calls.
# ruleid: py-shell-command
sp.run(cmd)
# ruleid: py-shell-command
system(cmd)
# ruleid: py-shell-command
os.posix_spawn(program, args, env)
# ruleid: py-shell-command
asyncio.create_subprocess_exec(program, *args)
# ruleid: py-shell-command
asyncio.create_subprocess_shell(cmd)
# ruleid: py-shell-command
pty.spawn(cmd)

# Legitimate research code. Nothing below may match.
# =========================================================================


def lookup_student(con, sid):
    # ok: py-sql-injection
    return con.execute("SELECT * FROM students WHERE id = ?", (sid,)).fetchall()


# ok: py-sql-injection
grades = pd.read_sql("SELECT school, AVG(gpa) FROM grades GROUP BY school", con)


def load_table(name):
    # ok: py-path-from-parameter
    with open(os.path.join("data", "grades.csv")) as fh:
        return fh.read()


tokens = essay.split()
# ok: py-secret-in-log
print(tokens)
n_tokens = len(tokens)
# ok: py-secret-in-log
print(f"token count: {n_tokens}")
# ok: py-secret-in-log
logging.info("Analysis complete")

# ok: py-hardcoded-password
db_password = os.environ["DB_PASSWORD"]
# ok: py-hardcoded-password
token_type = "word"


def fit(df):
    # ok: py-silent-exception
    try:
        return model.fit(df)
    except ValueError as e:
        logging.warning("fit failed: %s", e)
        return None


enrolled = df[df.status == "enrolled"]
# ok: py-assert-access-control
assert len(enrolled) > 0, "no enrolled students"
# ok: py-assert-access-control
assert df["role"].notna().all()


def unpack_data(path):
    with tarfile.open(path) as tf:
        # ok: py-tarfile-extractall
        tf.extractall("data", filter="data")
    with zipfile.ZipFile(path) as zf:
        # ok: py-tarfile-extractall
        zf.extractall("data")


# ok: py-insecure-mktemp
handle, scratch = tempfile.mkstemp(suffix=".csv")

# ok: py-dynamic-dispatch
summary = getattr(df, "describe")()


# ok: py-eval-exec
model.eval()
# ok: py-eval-exec
df = df.eval("gpa_delta = gpa_post - gpa_pre")
# ok: py-eval-exec
threshold = eval("10 ** 3")


# ok: py-local-deserialization
with open("config.json") as fh:
    settings = json.load(fh)

# ok: py-unsafe-yaml-load
params = yaml.safe_load(open("params.yaml"))
# ok: py-unsafe-yaml-load
params = yaml.load(open("params.yaml"), Loader=yaml.SafeLoader)


# ok: py-weak-hash, py-weak-hash-for-secret
digest = hashlib.sha256(payload).hexdigest()
# ok: py-weak-hash
checksum = hashlib.md5(payload, usedforsecurity=False).hexdigest()

# ok: py-weak-cipher
cipher = Crypto.Cipher.AES.new(key, Crypto.Cipher.AES.MODE_GCM)


def bootstrap_sample(df):
    # ok: py-insecure-random-for-secret
    return df.sample(frac=1.0, replace=True, random_state=random.randint(0, 10_000))


# ok: py-world-writable-permissions
os.chmod("results/summary.csv", 0o644)

# ok: py-xml-parser
tree = defusedxml.ElementTree.parse("lms_export.xml")

# ok: py-server-exposed
dash_app.run(host="127.0.0.1", port=8050)
