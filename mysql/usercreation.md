Hi Team,

I have placed the MySQL user creation script:

### Key Features

The script supports the following inputs:

1. **Hostname:** MySQL database hostname.
2. **Port Number:** MySQL database port.
3. **Username:** New MySQL username to be created.
4. **User Email ID:** The recipient's email address.
5. **Password:** Password for the new MySQL user.
6. **Schema Names:** Supports multiple schemas in a single execution.
7. **Privileges:** Supports multiple privileges based on the required access level.

### Supported Privilege Levels

- **Read/Write Access:** `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `EXECUTE`, `SHOW VIEW`, `CREATE`, `ALTER`, `REFERENCES`, `INDEX`, `CREATE VIEW`, `CREATE ROUTINE`, `ALTER ROUTINE`, `EVENT`, `DROP`, `TRIGGER`, `GRANT OPTION`, `CREATE TEMPORARY TABLES`, and `LOCK TABLES`.

- **Read-Only Access:** `SELECT`, `SHOW VIEW`.

### Email Notification

The script sends the newly created user's database connection details, including the hostname, port number, username, schema names, and privileges, directly to the user's email address. The password is also sent to the user's email address.

Please use this script for MySQL user creation.
