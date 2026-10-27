# Semgrep test target for semgrep-rules/r-security.yaml (run: pnpm test:semgrep).
#
# The first part is the OTTER-774 scanner fixture: deliberately insecure, never run it. Submitting
# this file as study code also checks the scanner end to end. The credentials are fake but
# format-shaped; secrets.r tests the rules that match them.
#
# The second part is ordinary research code that sits next to each pattern. Each "ok" line must not
# match, so a rule that starts to fire on legitimate analysis fails the test.

library(DBI)
library(httr)

# --- 1. Hardcoded credentials --------------------------------------------
# ruleid: r-hardcoded-password
AWS_ACCESS_KEY_ID <- "AKIAIOSFODNN7EXAMPLE"
# ruleid: r-hardcoded-password
AWS_SECRET_ACCESS_KEY <- "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
# ruleid: r-hardcoded-password
GITHUB_TOKEN <- "ghp_016C7869B4D4D2F1A9B3C7E8F0A1B2C3D4E5F6"
SLACK_WEBHOOK <- "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
STRIPE_KEY <- "sk_live_EXAMPLEEXAMPLEEXAMPLE00"
# ruleid: r-hardcoded-password
db_password <- "hunter2"

PRIVATE_KEY <- "-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAx7Vn9Q3mKp8L2wR5tZbF6yJhN1cD4eG7sA0uV3iX9oP2qWmE
-----END RSA PRIVATE KEY-----"

# --- 2. Arbitrary code execution from untrusted input --------------------
run_user_expr <- function(user_input) {
    # ruleid: r-eval-parse
    eval(parse(text = user_input))
}

apply_user_fn <- function(name, arg) {
    # ruleid: r-dynamic-call-from-parameter
    do.call(name, list(arg))
}

# --- 3. Command injection ------------------------------------------------
count_lines <- function(filename) {
    # ruleid: r-command-injection
    system(paste("wc -l", filename))
}

archive_dir <- function(d) {
    # ruleid: r-command-injection
    system(sprintf("tar czf /tmp/out.tgz %s", d), intern = TRUE)
}

# --- 4. SQL injection ----------------------------------------------------
find_user <- function(con, uid) {
    # ruleid: r-sql-injection
    dbGetQuery(con, paste0("SELECT * FROM users WHERE id = '", uid, "'"))
}

# --- 5. Insecure deserialization -----------------------------------------
load_remote_model <- function(url) {
    # ruleid: r-remote-deserialization
    readRDS(gzcon(url(url)))
}

# ruleid: r-deserialization-from-parameter
load_workspace <- function(path) load(path)

# --- 6. TLS verification disabled ----------------------------------------
# ruleid: r-tls-verification-disabled
httr::set_config(httr::config(ssl_verifypeer = 0L, ssl_verifyhost = 0L))
# ruleid: r-tls-verification-disabled
options(download.file.method = "curl", download.file.extra = "-k --insecure")

# ruleid: r-tls-verification-disabled
fetch <- function(u) httr::GET(u, httr::config(ssl_verifypeer = 0L))

# --- 7. Remote code download and execution -------------------------------
bootstrap <- function() {
    # ruleid: r-remote-code-execution
    source("http://packages.internal.example.com/bootstrap.R")
    # ruleid: r-remote-code-execution
    system("curl -sk https://example.com/install.sh | bash")
}

# --- 8. Weak cryptography and predictable randomness ---------------------
# ruleid: r-weak-hash-for-secret
hash_password <- function(pw) digest::digest(pw, algo = "md5")
set.seed(42)
# ruleid: r-predictable-token
session_token <- function() paste0(sample(letters, 16, TRUE), collapse = "")

# --- 9. Path traversal ---------------------------------------------------
read_report <- function(name) {
    # ruleid: r-path-from-parameter
    readLines(file.path("/srv/reports", name))
}

# --- 10. Insecure temp files and permissions -----------------------------
stash <- function(x) {
    p <- "/tmp/scratch.csv"
    write.csv(x, p)
    # ruleid: r-world-writable-permissions
    Sys.chmod(p, "777")
}

# --- 11. Secrets written to logs -----------------------------------------
connect <- function() {
    # ruleid: r-secret-in-log
    message("connecting with password: ", db_password)
    # ruleid: r-secret-in-log
    cat("token:", GITHUB_TOKEN, "\n", file = "/tmp/debug.log", append = TRUE)
}

# --- 12. Silent failure --------------------------------------------------
# ruleid: r-silent-failure
risky <- function(f) try(f(), silent = TRUE)

# --- 13. Near misses that still use the network ---------------------------
# Safe for the security rules, but a study must not make network calls at all, so
# privacy-r-network-call reports this. That is why it sits above the legitimate part.

# ok: r-tls-verification-disabled
resp <- httr::GET(api_url, httr::config(ssl_verifypeer = 1L))

# =========================================================================
# Legitimate research code. Nothing below may match.
# =========================================================================

# ok: r-eval-parse
two <- eval(parse(text = "1 + 1"))

# ok: r-dynamic-call-from-parameter
combined <- do.call(rbind, lapply(files, read.csv))
# ok: r-dynamic-call-from-parameter
stacked <- do.call("rbind", parts)
summarise_by <- function(df, fn) {
    # ok: r-dynamic-call-from-parameter
    do.call(aggregate, list(df$score, by = list(df$school), FUN = mean))
}

lookup_student <- function(con, sid) {
    # ok: r-sql-injection
    dbGetQuery(con, "SELECT * FROM students WHERE id = $1", params = list(sid))
}
# ok: r-sql-injection
enrolled <- dbGetQuery(con, glue::glue_sql("SELECT * FROM enrolment WHERE term = {term}", .con = con))

# ok: r-remote-deserialization
model <- readRDS("models/fit.rds")
# ok: r-deserialization-from-parameter
load("data/workspace.RData")


# ok: r-remote-code-execution
source("helpers.R")
# ok: r-remote-code-execution
source(file.path("R", "clean.R"))

# ok: r-weak-hash-for-secret
cache_key <- digest::digest(df, algo = "md5")

set.seed(2024)
# ok: r-predictable-token
boot_idx <- sample(nrow(df), replace = TRUE)
# ok: r-predictable-token
label <- paste0("group_", seq_len(5))

# ok: r-path-from-parameter
grades <- read.csv(file.path("data", "grades.csv"))

# ok: r-world-writable-permissions
Sys.chmod("results/summary.csv", "644")

# ok: r-secret-in-log
tokens <- tidytext::unnest_tokens(essays, word, text)
# ok: r-secret-in-log
print(tokens)
# ok: r-secret-in-log
message("token count: ", n_tokens)
# ok: r-secret-in-log
cat("Analysis complete\n")

# ok: r-hardcoded-password
password_col <- Sys.getenv("DB_PASSWORD")
# ok: r-hardcoded-password
token_type <- "word"

fit <- tryCatch(
    lm(score ~ hours, data = df),
    # ok: r-silent-failure
    error = function(e) {
        warning("model failed: ", conditionMessage(e))
        NULL
    }
)
# ok: r-silent-failure
res <- try(risky_step())
