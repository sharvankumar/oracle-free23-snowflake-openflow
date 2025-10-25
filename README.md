# Snowflake Oracle Connector Setup

This document provides step-by-step instructions for configuring Oracle Database Free 23ai for Snowflake OpenFlow connector using XStream technology.

## Overview

The `snowflake_oracle_setup.sql` script configures Oracle database with:
- GoldenGate replication enabled for XStream support
- Supplemental logging for change data capture
- XStream administrator user (c##xstreamadmin) with proper privileges
- XStream connect user (c##connectuser) for Snowflake connector
- XStream outbound server (XOUT1) configured for HR and CO schemas
- Proper container-based user management for CDB/PDB architecture

## Prerequisites

- Oracle Database Free 23ai running in Docker container
- SYSTEM user access with SYSDBA privileges
- HR and CO schemas populated with sample data
- Database in ARCHIVELOG mode (required for XStream)

## Step-by-Step Setup

### 1. Connect to Oracle Database as Sysdba and Enable ArchiveMode.

```bash
# SSH to your EC2 instance
ssh -i <your-key.pem> ec2-user@<InstancePublicIp>

# docker bash
docker exec -it sharvan-kumar-afe-oracle-free bash
```

# Connect to Oracle database as Sysdba
sqlplus -L / as sysdba

```sql
-- Check if database is in ARCHIVELOG mode
SELECT log_mode FROM v$database;
-- If not in ARCHIVELOG mode, enable it (requires database restart)
-- SHUTDOWN IMMEDIATE;
-- STARTUP MOUNT;
-- ALTER DATABASE ARCHIVELOG;
-- ALTER DATABASE OPEN;
```

### 2. Run the Snowflake Setup Script, as System user via ssh or SQL developer.

```bash
# SSH to your EC2 instance
ssh -i <your-key.pem> ec2-user@<InstancePublicIp>

# Connect to Oracle database as SYSTEM
docker exec -it sharvan-kumar-afe-oracle-free sqlplus system/<password>@localhost:1521/FREEPDB1
```

```sql
-- Run the complete setup script
@/path/to/snowflake_oracle_setup.sql

-- Or copy and paste the script content directly
```

### 3. Verify Configuration

```sql
-- Check XStream outbound server
SELECT server_name, status, connect_user, capture_user 
FROM dba_xstream_outbound_servers;

-- Check XStream capture process
SELECT capture_name, status, queue_name, source_database
FROM dba_capture;

-- Check supplemental logging
SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_all
FROM v$database;

-- Check user accounts
SELECT username, account_status, created 
FROM dba_users 
WHERE username IN ('XSTRMADMIN', 'XSTRMUSER', 'SNOWFLAKE_CONNECTOR');
```

## What the Script Creates

### Users Created:
- **c##xstreamadmin**: XStream administrator with full privileges (common user)
- **c##connectuser**: XStream server connect user (common user)

### XStream Components:
- **XOUT1**: XStream outbound server for data streaming
- **Source Container**: FREEPDB1 (Pluggable Database)
- **Schemas**: HR and CO schemas configured for capture

### Configuration:
- **GoldenGate Replication**: Enabled for XStream support
- **Supplemental Logging**: Enabled for all columns
- **Container Management**: Proper CDB/PDB user management
- **Privileges**: All necessary privileges granted for XStream operations

## Usage with Snowflake

### Connection Parameters for Snowflake:
- **Host**: `<InstancePublicIp>` or `<InstancePrivateIp>`
- **Port**: `1521`
- **Service**: `FREEPDB1`
- **Username**: `c##connectuser`
- **Password**: `ConnectUser123!`

### XStream Configuration:
- **XStream Server**: `XOUT1`
- **Source Container**: `FREEPDB1`
- **Schemas**: `HR`, `CO`
- **Connect User**: `c##connectuser`
- **Capture User**: `c##xstreamadmin`

## Monitoring and Troubleshooting

### Check XStream Status:
```sql
-- Check outbound server status
SELECT server_name, status, connect_user, capture_user, 
       created, last_enqueue_time, last_dequeue_time
FROM dba_xstream_outbound_servers;

-- Check GoldenGate replication setting
SELECT name, value FROM v$parameter WHERE name = 'enable_goldengate_replication';

-- Check supplemental logging
SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_all
FROM v$database;

-- Check user accounts
SELECT username, account_status, created, default_tablespace
FROM dba_users 
WHERE username IN ('c##xstreamadmin', 'c##connectuser')
ORDER BY username;
```

### Check Logs:
```sql
-- Check XStream logs
SELECT * FROM dba_xstream_log;

-- Check capture errors
SELECT * FROM dba_capture_errors;

-- Check queue statistics
SELECT * FROM dba_queue_tables;
```

### Common Issues:

#### 1. XStream Server Not Running
```sql
-- Check server status
SELECT server_name, status FROM dba_xstream_outbound_servers;

-- Restart server if needed
BEGIN
  DBMS_XSTREAM_ADM.ALTER_OUTBOUND_SERVER(
    server_name => 'XSTREAM_OUTBOUND_SERVER',
    status => 'ENABLED'
  );
END;
/
```

#### 2. Capture Process Not Running
```sql
-- Check capture status
SELECT capture_name, status FROM dba_capture;

-- Start capture if needed
BEGIN
  DBMS_CAPTURE_ADM.START_CAPTURE('XSTREAM_CAPTURE');
END;
/
```

#### 3. Supplemental Logging Issues
```sql
-- Verify supplemental logging
SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_all
FROM v$database;

-- Re-enable if needed
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
```

## Security Considerations

### Password Security:
- Change default passwords in production
- Use strong passwords (12+ characters)
- Store passwords securely

### Network Security:
- Restrict database access to authorized IPs
- Use SSL/TLS for connections
- Monitor database access logs

### User Privileges:
- Review granted privileges regularly
- Use least-privilege principle
- Monitor user activity

## Performance Impact

### XStream Overhead:
- Minimal impact on database performance
- Captures only committed transactions
- Efficient change data capture

### Monitoring:
```sql
-- Check XStream performance
SELECT server_name, total_messages, total_bytes,
       messages_per_second, bytes_per_second
FROM dba_xstream_outbound_servers;

-- Check capture performance
SELECT capture_name, total_messages_captured,
       total_messages_queued, total_messages_dequeued
FROM dba_capture;
```

## Cleanup (if needed)

### Remove XStream Configuration:
```sql
-- Stop and drop capture process
BEGIN
  DBMS_CAPTURE_ADM.STOP_CAPTURE('XSTREAM_CAPTURE');
  DBMS_CAPTURE_ADM.DROP_CAPTURE('XSTREAM_CAPTURE');
END;
/

-- Drop outbound server
BEGIN
  DBMS_XSTREAM_ADM.DROP_OUTBOUND_SERVER('XSTREAM_OUTBOUND_SERVER');
END;
/

-- Drop users
DROP USER XSTRMADMIN CASCADE;
DROP USER XSTRMUSER CASCADE;
DROP USER SNOWFLAKE_CONNECTOR CASCADE;
```

## Support and Documentation

### Snowflake Documentation:
- [Snowflake OpenFlow Connectors](https://docs.snowflake.com/LIMITEDACCESS/openflow/connectors/)
- [Oracle Connector Setup](https://docs.snowflake.com/LIMITEDACCESS/openflow/connectors/oracle/setup-connector)

### Oracle Documentation:
- [Oracle XStream Documentation](https://docs.oracle.com/en/database/oracle/oracle-database/19/streams/)
- [Oracle Change Data Capture](https://docs.oracle.com/en/database/oracle/oracle-database/19/streams/)

## Example Output

```
SQL> @snowflake_oracle_setup.sql

Database altered.
Database altered.
Database altered.

User created.

Grant succeeded.
Grant succeeded.
...

PL/SQL procedure successfully completed.

PL/SQL procedure successfully completed.

PL/SQL procedure successfully completed.

Snowflake Oracle Connector setup completed successfully!
XStream users created: XSTRMADMIN, XSTRMUSER, SNOWFLAKE_CONNECTOR
XStream outbound server: XSTREAM_OUTBOUND_SERVER
XStream capture process: XSTREAM_CAPTURE
Supplemental logging enabled for all columns and primary keys
HR and CO schemas configured for XStream capture
```

## Next Steps

1. **Configure Snowflake Connector**: Use the connection parameters in Snowflake
2. **Test Data Flow**: Verify data is being captured and streamed
3. **Monitor Performance**: Set up monitoring for XStream components
4. **Scale as Needed**: Add more tables or schemas to capture process

The Oracle database is now ready for Snowflake OpenFlow connector integration! 🎉
