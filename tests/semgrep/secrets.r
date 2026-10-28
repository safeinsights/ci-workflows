# Semgrep test target for semgrep-rules/secrets.yaml (run: pnpm test:semgrep).
# The credentials are fake but format-shaped. The rules are regex rules, so the file language does
# not matter; R is used because study code is mostly R.

# ruleid: secret-private-key
pem <- "-----BEGIN OPENSSH PRIVATE KEY-----"
# ruleid: secret-private-key
pem2 <- "-----BEGIN PRIVATE KEY-----"
# ruleid: secret-aws-access-key-id
key_id <- "AKIAIOSFODNN7EXAMPLE"
# ruleid: secret-aws-access-key-id
session_key_id <- "ASIAY34FZKBOKMUTVV7A"
# ruleid: secret-aws-secret-access-key
AWS_SECRET_ACCESS_KEY <- "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
# ruleid: secret-github-token
GITHUB_TOKEN <- "ghp_016C7869B4D4D2F1A9B3C7E8F0A1B2C3D4E5F6"
# ruleid: secret-github-token
pat <- "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"
# ruleid: secret-gitlab-token
gl <- "glpat-DxtpYlSXpfKtHF4vUCsM"
# ruleid: secret-slack
slack_bot <- "xoxb-118625276018-955597971147-SQedUStPKR0CsTy4Qwb8DwkN"
# ruleid: secret-slack
hook <- "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
# ruleid: secret-stripe-key
STRIPE_KEY <- "sk_live_EXAMPLEEXAMPLEEXAMPLE00"
# ruleid: secret-google-api-key
maps_key <- "AIzahFdnXsiVpzz63FfkCzJr4i0B3JrTAwR4y9o"
# ruleid: secret-google-api-key
oauth <- "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"
# ruleid: secret-ai-api-key
openai <- "sk-proj-NPRVdD53X83RZJzzzzgEOzdmenCkhvMdgaKjIg8xT3BlbkFJNbe3nNyjOq9wMxEhh2FDEEtfjgVvVqE1SkHbn88H"
# ruleid: secret-ai-api-key
claude <- "sk-ant-api03-xjSI6bWHtP3fS2qHx6kwXoIIXGvOoNZYW2mZp0zVZomHFwUbbYrEqmSM9wCZ7Uw9xfogoEmvnEN5N1aE6PwZPf1Qh6yYT"
# ruleid: secret-ai-api-key
hf <- "hf_WmE4lBYOvfZ8UzDzV8fUkkibjL5DZPjN0M"
# ruleid: secret-sendgrid-key
sg <- "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"
# ruleid: secret-azure-storage-key
az <- "DefaultEndpointsProtocol=https;AccountName=x;AccountKey=atws8phP9nhFyJfm5di4PzJ59FHz5r1pY4OjE2jBMptUsGr7CmY+uCu3ZR1zTOlUcR64cXQLioDnkHIfxIq2HZ==;"
# ruleid: secret-connection-string-password
db_url <- "postgresql://analyst:s3cr3t-Pa55@db.example.org:5432/study"
# ruleid: secret-jwt
jwt <- "eyJjI6GKFSufrdZSlB5er8b.eyJOfZqfM2oeq3hDavJA76rNicHTp8hkq.dlm7tOtHWnsCGRlrwZbqcabUGJmGEp7CgQ0PBQFI14z"

# Near misses: ordinary values that share a prefix or shape with a credential.

# ok: secret-aws-access-key-id
student_id <- "AKIA1234"
# ok: secret-aws-secret-access-key
aws_region <- "us-east-1"
# ok: secret-github-token
repo <- "https://github.com/safeinsights/research-code-review"
# ok: secret-stripe-key
test_key <- "sk_test_EXAMPLEEXAMPLEEXAMPLE00"
# ok: secret-ai-api-key
model_name <- "sk-learn-baseline"
# ok: secret-connection-string-password
db_url <- paste0("postgresql://analyst:", Sys.getenv("DB_PASSWORD"), "@db:5432/study")
# ok: secret-connection-string-password
tmpl <- "postgresql://${DB_USER}:${DB_PASSWORD}@db:5432/study"
# ok: secret-connection-string-password
no_pw <- "postgresql://analyst@db:5432/study"
# ok: secret-private-key
pub <- "-----BEGIN PUBLIC KEY-----"
# ok: secret-jwt
hdr <- "eyJhbGciOi"
