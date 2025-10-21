

# 🗄️ MongoDB Schema Backup Script

This Bash script automates the **MongoDB schema backup** process for Non-Production environments.
It performs a `mongodump` (schema-only), verifies database existence, logs the operation, and sends an **HTML-formatted email notification** with the backup status.

---

## 🧩 Features

✅ Checks if the specified MongoDB database exists before backup
✅ Performs schema-only backup using `mongodump`
✅ Logs all backup activities
✅ Sends email notifications with success or failure status
✅ HTML-styled email for easy readability

---

## ⚙️ Configuration

Before running the script, update the following variables in the script:

### 🔧 Email Configuration

```bash
TO=""          # Recipient email address
FROM=""        # Sender email (configured in msmtp)
SUBJECT="MongoDB Backup Status - Non Prod"
```

### 🗃️ MongoDB Configuration

```bash
MONGO_HOST=""  # MongoDB host or IP
MONGO_PORT=""  # MongoDB port (e.g., 27017)
MONGO_USER=""  # MongoDB username
MONGO_PWD=''   # MongoDB password (keep in single quotes)
MONGO_DB=""    # Target database name
```

### 📁 Directory & Logging

```bash
BACKUP_DIR=""   # Root directory for backups
OUTPUT_DIR=""   # Directory to store this run’s dump
LOG_FILE=""     # Path to log file
```

Ensure these directories exist and are writable by the script.

---

## 🚀 How It Works

1. **Checks database existence**

   * Uses `mongosh` to verify if `$MONGO_DB` exists on the target server.
   * If not found, it sends a failure email.

2. **Performs schema-only backup**

   * Executes `mongodump` for the specified DB.
   * Includes users and roles using `--dumpDbUsersAndRoles`.

3. **Generates HTML email**

   * Builds a formatted HTML email with color-coded success/failure status.

4. **Sends notification**

   * Uses `msmtp` for sending the email to configured recipients.

---

## 📧 Email Output Example

**Subject:** `MongoDB Backup Status - Non Prod`
**Body:**

| Field           | Description                |
| --------------- | -------------------------- |
| **Status**      | ✅ Success / ❌ Failed       |
| **Database**    | Database name              |
| **Backup Time** | Timestamp of backup        |
| **Message**     | Reason for success/failure |

---

## 🪄 Example Command

```bash
chmod +x mongodb_backup.sh
./mongodb_backup.sh
```

---

## 🧠 Requirements

* `mongosh`
* `mongodump`
* `msmtp`
* Bash environment (Linux or macOS)

Ensure `msmtp` is configured properly in `/etc/msmtprc` or `~/.msmtprc`.

---

## 📝 Log File Example

```
Starting MongoDB schema-only backup...
2025-10-21T06:40:00 Dumping users and roles for database testdb
2025-10-21T06:40:01 Backup completed successfully.
```

---

## 🧰 Troubleshooting

| Issue                | Possible Cause         | Fix                                         |
| -------------------- | ---------------------- | ------------------------------------------- |
| `Access denied`      | Wrong credentials      | Verify `MONGO_USER` and `MONGO_PWD`         |
| `Database not found` | DB name incorrect      | Check `$MONGO_DB` spelling                  |
| `Email not sent`     | `msmtp` not configured | Set up sender credentials in `msmtp` config |


