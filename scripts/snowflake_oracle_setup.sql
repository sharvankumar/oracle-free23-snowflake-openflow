-- Snowflake Oracle Connector Setup Script
-- This script configures Oracle database for Snowflake OpenFlow connector
-- Based on official Snowflake documentation
-- Run as SYSTEM user with SYSDBA privileges

-- =============================================
-- 1. Enable XStream and Supplemental Logging
-- =============================================

-- Enable GoldenGate replication (required for XStream)
ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;

-- Check database log mode
SELECT LOG_MODE FROM V$DATABASE;

-- Switch to root container for supplemental logging
ALTER SESSION SET CONTAINER = CDB$ROOT;

-- Enable supplemental logging for all columns
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- =============================================
-- 2. Create Tablespaces for XStream
-- =============================================

-- Create tablespace for XStream administrator in root container
CREATE TABLESPACE xstream_adm_tbs DATAFILE '/opt/oracle/oradata/FREE/xstream_adm_tbs.dbf'
   SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;

-- Switch to PDB and create tablespace there
ALTER SESSION SET CONTAINER = FREEPDB1;

CREATE TABLESPACE xstream_adm_tbs DATAFILE '/opt/oracle/oradata/FREE/FREEPDB1/xstream_adm_tbs.dbf'
   SIZE 25M REUSE AUTOEXTEND ON MAXSIZE UNLIMITED;

-- Switch back to root container
ALTER SESSION SET CONTAINER = CDB$ROOT;

-- =============================================
-- 3. Create XStream Administrator User
-- =============================================

-- Create XStream administrator user (common user with c## prefix)
CREATE USER c##xstreamadmin IDENTIFIED BY "XStreamAdmin123!"
   DEFAULT TABLESPACE xstream_adm_tbs
   QUOTA UNLIMITED ON xstream_adm_tbs
   CONTAINER=ALL;

-- =============================================
-- 4. Grant XStream Administrator Privileges
-- =============================================
-- Grant basic system privileges
GRANT CREATE SESSION, SET CONTAINER, EXECUTE ANY PROCEDURE, LOGMINING TO c##xstreamadmin CONTAINER=ALL;

-- Grant XSTREAM_CAPTURE role (THIS WORKS!)
GRANT XSTREAM_CAPTURE TO c##xstreamadmin CONTAINER=ALL;

-- Grant additional privileges
GRANT SELECT ANY TABLE TO c##xstreamadmin CONTAINER=ALL;
GRANT FLASHBACK ANY TABLE TO c##xstreamadmin CONTAINER=ALL;
GRANT SELECT ANY TRANSACTION TO c##xstreamadmin CONTAINER=ALL;

-- Try to grant XSTREAM_ADMIN role (may or may not work)
BEGIN
    EXECUTE IMMEDIATE 'GRANT XSTREAM_ADMIN TO c##xstreamadmin CONTAINER=ALL';
    DBMS_OUTPUT.PUT_LINE('XSTREAM_ADMIN role granted successfully');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('XSTREAM_ADMIN role not available: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Continuing with XSTREAM_CAPTURE role only');
END;
/
   
-- =============================================
-- 5. Configure XStream Server Connect User
-- =============================================

-- Create XStream server connect user (common user with c## prefix)
CREATE USER c##connectuser IDENTIFIED BY "ConnectUser123!"
    CONTAINER=ALL;

-- Grant necessary privileges to the connect user
GRANT CREATE SESSION, SELECT_CATALOG_ROLE TO c##connectuser CONTAINER=ALL;
GRANT SELECT ANY TABLE TO c##connectuser CONTAINER=ALL;
GRANT LOCK ANY TABLE TO c##connectuser CONTAINER=ALL;

-- =============================================
-- 6. Create XStream Outbound Server
-- =============================================

-- Enable server output to see messages
SET SERVEROUTPUT ON;

-- Create XStream Outbound Server for HR and CO schemas in FREEPDB1
DECLARE
    tables  DBMS_UTILITY.UNCL_ARRAY;
    schemas DBMS_UTILITY.UNCL_ARRAY;
BEGIN
    -- Configure to capture HR and CO schemas from FREEPDB1
    tables(1) := NULL;
    schemas(1) := 'HR';
    schemas(2) := 'CO';
    
    DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
        server_name => 'XOUT1',
        table_names => tables,
        schema_names => schemas,
        source_container_name => 'FREEPDB1'
    );
    DBMS_OUTPUT.PUT_LINE('XStream Outbound Server created for HR and CO schemas.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error creating XStream Outbound Server: ' || SQLERRM);
        RAISE;
END;
/

-- =============================================
-- 7. Set XStream Outbound Server Connect User
-- =============================================

-- Set the connect user on the XStream Outbound Server
BEGIN
    DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
        server_name  => 'XOUT1',
        connect_user => 'c##connectuser');
END;
/

-- =============================================
-- 8. Set XStream Outbound Server Capture User
-- =============================================

-- Set the capture user on the XStream Outbound Server
BEGIN
    DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
        server_name  => 'XOUT1',
        capture_user => 'c##xstreamadmin');
END;
/

-- =============================================
-- 9. Verify XStream Configuration
-- =============================================

-- Check XStream outbound server status
SELECT server_name, status, connect_user, capture_user 
FROM dba_xstream_outbound;

-- Check if supplemental logging is enabled
SELECT supplemental_log_data_min, supplemental_log_data_pk, supplemental_log_data_all
FROM v$database;

/* 
For XStream:
-- supplemental_log_data_all = YES - Captures all column changes
-- supplemental_log_data_min = IMPLICIT - Ensures minimal logging is active
-- supplemental_log_data_pk = NO - Not needed when ALL is enabled
For Snowflake OpenFlow:
-- Complete change capture - All column modifications are tracked
-- Real-time replication - Changes are immediately available
-- Data consistency - Full column data for accurate replication
*/ 

-- Check user accounts exists in all containers

SELECT con_id, username, account_status
FROM   cdb_users
WHERE  username IN ('C##XSTRMCAPTURE','C##CONNECTUSER')
ORDER  BY con_id;

-- Quotas present?
SELECT con_id, username, tablespace_name, max_bytes
FROM   cdb_ts_quotas
WHERE  username IN ('C##XSTRMCAPTURE','C##CONNECTUSER');

-- =============================================
-- 10. Final Verification and Summary
-- =============================================

-- Check GoldenGate replication setting
SELECT name, value FROM v$parameter WHERE name = 'enable_goldengate_replication';

-- Check database log mode
SELECT log_mode FROM v$database;

-- Check XStream outbound server configuration
SELECT server_name, status, connect_user, capture_user
FROM dba_xstream_outbound;

-- Check user accounts and status
SELECT con_id, username, account_status
FROM   cdb_users
WHERE  username IN ('C##XSTRMCAPTURE','C##CONNECTUSER')
ORDER BY username;

-- Check  the capture name and messages
SELECT CAPTURE_NAME,
       STATE,
       TOTAL_MESSAGES_CAPTURED,
       TOTAL_MESSAGES_ENQUEUED 
  FROM V$XSTREAM_CAPTURE;

-- Check  all stream rules.
select * from ALL_XSTREAM_RULES;

-- =============================================
-- Script completed successfully
-- =============================================

PROMPT '=============================================';
PROMPT 'Snowflake Oracle Connector setup completed!';
PROMPT '=============================================';
PROMPT 'XStream users created:';
PROMPT '- c##xstreamadmin (XStream administrator)';
PROMPT '- c##connectuser (XStream connect user)';
PROMPT '';
PROMPT 'XStream outbound server: XOUT1';
PROMPT 'Source container: FREEPDB1';
PROMPT 'Schemas configured: HR, CO';
PROMPT '';
PROMPT 'Connection parameters for Snowflake:';
PROMPT 'Host: <InstancePublicIp> or <InstancePrivateIp>';
PROMPT 'Port: 1521';
PROMPT 'Service: FREEPDB1';
PROMPT 'Username: c##connectuser';
PROMPT 'Password: ConnectUser123!';
PROMPT '';
PROMPT 'Supplemental logging enabled for all columns';
PROMPT 'GoldenGate replication enabled';
PROMPT '=============================================';
