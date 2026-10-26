
#!/usr/bin/env bash

set -o pipefail
umask 077

# ============================================================
# 1. AWS SECRETS MANAGER CONFIGURATION
# ============================================================
SECRET_NAME="<secretname>"
AWS_REGION="<region>"

# ============================================================
# 2. EMAIL CONFIGURATION
# ============================================================
FROM="<from email>"

# Cloud Support receives the provisioning status report.
SUPPORT_EMAILS=(
  "<to emails>"
)

# The new database user's email is entered at runtime.
USER_EMAIL=""

# ============================================================
# 3. LOG CONFIGURATION
# ============================================================
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_DIR="/home/ec2-user/scripts/logs"
LOG_FILE="${LOG_DIR}/usercreation_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR" || exit 1
touch "$LOG_FILE" || exit 1
chmod 600 "$LOG_FILE" || exit 1

log() {
    printf '[%s] %s\n' \
        "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

# ============================================================
# 4. INITIALIZE VARIABLES
# ============================================================
MYSQL_HOST=""
MYSQL_PORT=""
MYSQL_USER=""
MYSQL_PASS=""
NEW_USER=""
NEW_PASS=""
SCHEMAS=""
PRIVS_DISPLAY=""
STATUS="FAILED"
DETAILS="The operation did not complete."
MYSQL_CNF=""
USER_EMAIL_STATUS="NOT SENT"
GRANT_OPTION="0"

# ============================================================
# 5. CLEANUP
# ============================================================
cleanup() {
    if [[ -n "$MYSQL_CNF" && -f "$MYSQL_CNF" ]]; then
        rm -f -- "$MYSQL_CNF"
    fi

    unset MYSQL_PASS NEW_PASS SQL_COMMAND SQL_PASS
    unset SECRET_JSON ESCAPED_PASS ESCAPED_USER
}

trap cleanup EXIT

# ============================================================
# 6. EMAIL HELPERS
# ============================================================
send_email() {
    local recipient="$1"
    local subject="$2"
    local body="$3"

    {
        printf 'From: %s\n' "$FROM"
        printf 'To: %s\n' "$recipient"
        printf 'Subject: %s\n' "$subject"
        printf 'MIME-Version: 1.0\n'
        printf 'Content-Type: text/plain; charset=UTF-8\n'
        printf '\n%s\n' "$body"
    } | msmtp -- "$recipient"
}

send_status_email() {
    local subject
    local recipients
    local body

    recipients=$(IFS=', '; printf '%s' "${SUPPORT_EMAILS[*]}")
    subject="MySQL User Provisioning - ${STATUS} - ${NEW_USER:-Unknown}"

    body="MySQL User Provisioning Report
========================================
Execution time : $(date '+%Y-%m-%d %H:%M:%S %Z')
MySQL hostname : ${MYSQL_HOST:-Not provided}
MySQL port     : ${MYSQL_PORT:-Not provided}
Username       : ${NEW_USER:-Not provided}
User email     : ${USER_EMAIL:-Not provided}
Schemas        : ${SCHEMAS:-Not provided}
Privileges     : ${PRIVS_DISPLAY:-Not provided}
Status         : ${STATUS}
User email     : ${USER_EMAIL_STATUS}

Details:
${DETAILS}

Log file:
${LOG_FILE}

Cloud Platform Team
"

    {
        printf 'From: %s\n' "$FROM"
        printf 'To: %s\n' "$recipients"
        printf 'Subject: %s\n' "$subject"
        printf 'MIME-Version: 1.0\n'
        printf 'Content-Type: text/plain; charset=UTF-8\n'
        printf '\n%s\n' "$body"
    } | msmtp -- "${SUPPORT_EMAILS[@]}"
}

send_user_credentials() {
    local body

    body="MySQL Account Provisioning Details
========================================
Status         : SUCCESS
Hostname       : ${MYSQL_HOST}
Port           : ${MYSQL_PORT}
Username       : ${NEW_USER}
Password       : ${NEW_PASS}
Schemas        : ${SCHEMAS}
Privileges     : ${PRIVS_DISPLAY}
Created at     : $(date '+%Y-%m-%d %H:%M:%S %Z')

Please store these credentials securely.
Cloud Platform Team
"

    send_email \
        "$USER_EMAIL" \
        "MySQL Account Details - ${NEW_USER}" \
        "$body"
}

# ============================================================
# 7. FAILURE HANDLER
# ============================================================
fail() {
    DETAILS="$1"
    STATUS="FAILED"

    log "ERROR: $DETAILS"

    if command -v msmtp >/dev/null 2>&1; then
        if ! send_status_email; then
            log "ERROR: Status email notification failed."
        fi
    fi

    exit 1
}

# ============================================================
# 8. CHECK REQUIRED COMMANDS
# ============================================================
for cmd in aws jq mysql msmtp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "Required command is not installed: $cmd"
    fi
done

# ============================================================
# 9. RETRIEVE ADMIN CREDENTIALS FROM SECRETS MANAGER
# ============================================================
log "Retrieving administrative credentials from Secrets Manager."

if ! SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$AWS_REGION" \
    --query SecretString \
    --output text \
    --no-cli-pager 2>>"$LOG_FILE"); then

    fail "Unable to retrieve secret: $SECRET_NAME"
fi

if ! MYSQL_USER=$(jq -er \
    '.BASH_USER | select(type == "string" and length > 0)' \
    <<< "$SECRET_JSON") ||
   ! MYSQL_PASS=$(jq -er \
    '.BASH_PWD | select(type == "string" and length > 0)' \
    <<< "$SECRET_JSON"); then

    unset SECRET_JSON
    fail "Secret must contain non-empty BASH_USER and BASH_PWD keys."
fi

unset SECRET_JSON
log "Administrative credentials retrieved successfully."

# ============================================================
# 10. COLLECT USER INPUTS
# ============================================================
read -r -p "Enter MySQL hostname: " MYSQL_HOST
read -r -p "Enter MySQL port [3306]: " MYSQL_PORT
MYSQL_PORT=${MYSQL_PORT:-3306}

read -r -p "Enter new username: " NEW_USER
read -r -p "Enter recipient email address: " USER_EMAIL
read -r -s -p "Enter password for new user: " NEW_PASS
printf '\n'

read -r -p "Enter schema names (comma-separated): " SCHEMAS

read -r -p "Enter privileges (comma-separated): " PRIVS_INPUT

# ============================================================
# 11. VALIDATE INPUTS
# ============================================================
if [[ ! "$MYSQL_HOST" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
    fail "Invalid MySQL hostname."
fi

if [[ ! "$MYSQL_PORT" =~ ^[0-9]+$ ]] ||
   (( MYSQL_PORT < 1 || MYSQL_PORT > 65535 )); then
    fail "Invalid MySQL port."
fi

if [[ ! "$NEW_USER" =~ ^[a-zA-Z0-9_]+$ ]]; then
    fail "Invalid MySQL username."
fi

if [[ -z "$NEW_PASS" || -z "$SCHEMAS" || -z "$PRIVS_INPUT" ]]; then
    fail "Password, schemas and privileges are required."
fi

if [[ ! "$USER_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    fail "Invalid recipient email address."
fi

# ============================================================
# 12. VALIDATE SCHEMAS
# ============================================================
IFS=',' read -r -a SCHEMA_ARRAY <<< "$SCHEMAS"
declare -A SEEN_SCHEMAS

for i in "${!SCHEMA_ARRAY[@]}"; do
    SCHEMA_ARRAY[$i]="${SCHEMA_ARRAY[$i]//[[:space:]]/}"

    if [[ ! "${SCHEMA_ARRAY[$i]}" =~ ^[a-zA-Z0-9_]+$ ]]; then
        fail "Invalid schema name supplied."
    fi

    if [[ -n "${SEEN_SCHEMAS[${SCHEMA_ARRAY[$i]}]+exists}" ]]; then
        fail "Duplicate schema supplied: ${SCHEMA_ARRAY[$i]}"
    fi

    SEEN_SCHEMAS["${SCHEMA_ARRAY[$i]}"]=1
done

SCHEMAS=$(IFS=', '; printf '%s' "${SCHEMA_ARRAY[*]}")

# ============================================================
# 13. VALIDATE AND NORMALIZE PRIVILEGES
# ============================================================
PRIVS_INPUT=${PRIVS_INPUT^^}
PRIVS_INPUT=${PRIVS_INPUT//[[:space:]]/}

IFS=',' read -r -a PRIV_ARRAY <<< "$PRIVS_INPUT"

SQL_PRIVS=()
declare -A SEEN_PRIVS
GRANT_OPTION="0"

for privilege in "${PRIV_ARRAY[@]}"; do
    case "$privilege" in
        SELECT)                 SQL_PRIVILEGE="SELECT" ;;
        INSERT)                 SQL_PRIVILEGE="INSERT" ;;
        UPDATE)                 SQL_PRIVILEGE="UPDATE" ;;
        DELETE)                 SQL_PRIVILEGE="DELETE" ;;
        EXECUTE)                SQL_PRIVILEGE="EXECUTE" ;;
        SHOWVIEW)               SQL_PRIVILEGE="SHOW VIEW" ;;
        CREATE)                 SQL_PRIVILEGE="CREATE" ;;
        ALTER)                  SQL_PRIVILEGE="ALTER" ;;
        REFERENCES)             SQL_PRIVILEGE="REFERENCES" ;;
        INDEX)                  SQL_PRIVILEGE="INDEX" ;;
        CREATEVIEW)             SQL_PRIVILEGE="CREATE VIEW" ;;
        CREATEROUTINE)          SQL_PRIVILEGE="CREATE ROUTINE" ;;
        ALTERROUTINE)           SQL_PRIVILEGE="ALTER ROUTINE" ;;
        EVENT)                  SQL_PRIVILEGE="EVENT" ;;
        DROP)                   SQL_PRIVILEGE="DROP" ;;
        TRIGGER)                SQL_PRIVILEGE="TRIGGER" ;;
        CREATETEMPORARYTABLES)  SQL_PRIVILEGE="CREATE TEMPORARY TABLES" ;;
        LOCKTABLES)             SQL_PRIVILEGE="LOCK TABLES" ;;
        GRANTOPTION)
            GRANT_OPTION="1"
            continue
            ;;
        *)
            fail "Unsupported privilege: $privilege"
            ;;
    esac

    if [[ -n "${SEEN_PRIVS[$SQL_PRIVILEGE]+exists}" ]]; then
        fail "Duplicate privilege supplied: $SQL_PRIVILEGE"
    fi

    SEEN_PRIVS["$SQL_PRIVILEGE"]=1
    SQL_PRIVS+=("$SQL_PRIVILEGE")
done

if (( ${#SQL_PRIVS[@]} == 0 )); then
    fail "At least one actual privilege must be supplied."
fi

PRIVS_DISPLAY=$(IFS=', '; printf '%s' "${SQL_PRIVS[*]}")

if [[ "$GRANT_OPTION" == "1" ]]; then
    PRIVS_DISPLAY+=", GRANT OPTION"
fi

PRIVS_SQL="$PRIVS_DISPLAY"

log "MySQL host: $MYSQL_HOST"
log "MySQL port: $MYSQL_PORT"
log "Requested username: $NEW_USER"
log "Requested schemas: $SCHEMAS"
log "Requested privileges: $PRIVS_DISPLAY"

# ============================================================
# 14. CREATE SECURE MYSQL CLIENT CONFIGURATION
# ============================================================
MYSQL_CNF=$(mktemp) ||
    fail "Could not create temporary MySQL configuration."

chmod 600 "$MYSQL_CNF" ||
    fail "Could not secure temporary MySQL configuration."

ESCAPED_PASS=${MYSQL_PASS//\\/\\\\}
ESCAPED_PASS=${ESCAPED_PASS//\"/\\\"}
ESCAPED_USER=${MYSQL_USER//\\/\\\\}
ESCAPED_USER=${ESCAPED_USER//\"/\\\"}

{
    printf '[client]\n'
    printf 'user="%s"\n' "$ESCAPED_USER"
    printf 'password="%s"\n' "$ESCAPED_PASS"
} > "$MYSQL_CNF" ||
    fail "Could not write MySQL client configuration."

unset ESCAPED_PASS ESCAPED_USER MYSQL_PASS

mysql_exec() {
    mysql --defaults-extra-file="$MYSQL_CNF" \
        --connect-timeout=10 \
        --batch --skip-column-names "$@"
}

# ============================================================
# 15. VERIFY SCHEMAS
# ============================================================
log "Checking requested schemas."

for SCHEMA in "${SCHEMA_ARRAY[@]}"; do
    if ! DB_CHECK=$(mysql_exec \
        -h "$MYSQL_HOST" -P "$MYSQL_PORT" \
        -e "SELECT SCHEMA_NAME
            FROM INFORMATION_SCHEMA.SCHEMATA
            WHERE SCHEMA_NAME = '${SCHEMA}'" \
        2>>"$LOG_FILE"); then

        fail "Could not verify schema: $SCHEMA"
    fi

    if [[ "$DB_CHECK" != "$SCHEMA" ]]; then
        fail "Schema does not exist or is not visible: $SCHEMA"
    fi

    log "Schema exists: $SCHEMA"
done

# ============================================================
# 16. CHECK WHETHER USER EXISTS
# ============================================================
log "Checking whether the requested account already exists."

if ! USER_CHECK=$(mysql_exec \
    -h "$MYSQL_HOST" -P "$MYSQL_PORT" \
    -e "SELECT COUNT(*)
        FROM mysql.user
        WHERE User = '${NEW_USER}' AND Host = '%'" \
    2>>"$LOG_FILE"); then

    fail "Could not check existing account. Verify administrative permissions."
fi

if [[ "$USER_CHECK" != "0" ]]; then
    fail "User ${NEW_USER}@% already exists. No changes made."
fi

# ============================================================
# 17. CREATE USER AND GRANT PRIVILEGES
# ============================================================
log "Creating user and assigning privileges."

# Double single quotes for SQL string-literal escaping.
SQL_PASS=${NEW_PASS//\'/\'\'}

SQL_COMMAND="CREATE USER '${NEW_USER}'@'%' IDENTIFIED BY '${SQL_PASS}';"

for SCHEMA in "${SCHEMA_ARRAY[@]}"; do
    SQL_COMMAND+="
GRANT ${SQL_PRIVS} ON \`${SCHEMA}\`.* TO '${NEW_USER}'@'%'"

    if [[ "$GRANT_OPTION" == "1" ]]; then
        SQL_COMMAND+=" WITH GRANT OPTION"
    fi

    SQL_COMMAND+=";"
done

if printf '%s\n' "$SQL_COMMAND" |
    mysql_exec -h "$MYSQL_HOST" -P "$MYSQL_PORT" \
        >>"$LOG_FILE" 2>&1; then

    STATUS="SUCCESS"
    DETAILS="User created and requested privileges granted on the listed schemas."
    log "SUCCESS: User created and privileges assigned."

else
    STATUS="FAILED"
    DETAILS="User creation or a privilege grant failed. Partial changes may have occurred. Check the log and database grants."
    log "ERROR: User creation or privilege assignment failed."

    unset SQL_COMMAND SQL_PASS

    if ! send_status_email; then
        log "ERROR: Support status email failed."
    fi

    exit 1
fi

unset SQL_COMMAND SQL_PASS

# ============================================================
# 18. SEND CREDENTIAL EMAIL TO REQUESTED USER
# ============================================================
if send_user_credentials; then
    USER_EMAIL_STATUS="SENT"
    log "Credential email sent to requested user."
else
    USER_EMAIL_STATUS="FAILED"
    DETAILS="User and grants were created successfully, but the credential email failed."
    log "ERROR: Credential email failed."
fi

# Clear password from the shell variable after the email attempt.
unset NEW_PASS

# ============================================================
# 19. SEND SUPPORT REPORT
# ============================================================
if [[ "$USER_EMAIL_STATUS" == "FAILED" ]]; then
    STATUS="SUCCESS - CREDENTIAL EMAIL FAILED"
fi

if send_status_email; then
    log "Support status email sent successfully."
else
    log "ERROR: Support status email failed."
fi

# ============================================================
# 20. COMPLETED
# ============================================================
log "User provisioning script completed."
