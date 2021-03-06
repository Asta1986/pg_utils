-------
--CSV--
-------
--Import table/column from CSV file.
COPY column_name FROM '/path/to/csv' DELIMITER ',' CSV encoding 'latin-1';

--If the first row contains column names.
COPY column_name FROM '/path/to/csv' DELIMITER ',' CSV HEADER;

--Export table/query result to CSV.
COPY table_name TO '/path/to/csv' DELIMITER ',' CSV HEADER;


-------------
--FUNCTIONS--
-------------
-- Erase all schemas (except system ones) and contained objects in the current database.
CREATE OR REPLACE FUNCTION erase_all_schemas()
    RETURNS void
    AS $f$
DECLARE
    sch text;
BEGIN
    FOR sch IN SELECT nspname FROM pg_namespace where nspname not like '%pg_%'
    LOOP
        EXECUTE format($$ drop SCHEMA %I CASCADE $$, sch);
    END LOOP;
END;
$f$ LANGUAGE plpgsql;

--Set cell values of text columns in a table to lower case.
--First parameter is the schema name and the second one the table name.
CREATE OR REPLACE FUNCTION text_columns_to_lowercase(sch_nm text, tab_nm text)
    RETURNS void
LANGUAGE plpgsql
    AS $f$
DECLARE
    col text;
BEGIN
    FOR col IN SELECT column_name
               FROM information_schema.columns
               WHERE table_name=tab_nm and data_type in ('text', 'char', 'character varying')
    LOOP
        EXECUTE format($$ update %I.%I set %I = lower(%I) $$, sch_nm, tab_nm, col, col);
    END LOOP;
END;
$f$;

--Transform a string with google maps point coordinates to WGS84 WKT.
--ex.: select gmapsCoordsToWKT('-34.618000, -58.388972');
CREATE OR REPLACE FUNCTION gmapsCoordsToWKT(coords text)
  RETURNS text AS
$BODY$
    with sub as (
        SELECT 'POINT(' || ltrim(split_part($1, ',', 2)) || ' ' || split_part($1, ',', 1) || ')' as p)
    select st_astext(ST_GeomFromText(sub.p, 4326)) from sub;
$BODY$
  LANGUAGE sql immutable;


------------------
--DUPLICATE ROWS--
------------------
--Compare rows according to values in the columns passed to partition by. Unique rows take a value of 1.
SELECT row_number() OVER (PARTITION BY columnA_name, columnB_name)
FROM table_name;


----------------
--PIVOT TABLES--
----------------
--Using crosstab (requires package postgresql-contrib).
CREATE extension tablefunc;
 
--crosstab(text, text); First query determines the groups (1st column row values, 2nd..n columns column values,
--last column cell value for each group i. e. count(*)). Second query generates a series of size n
--where n equals the number of columns and its values (select distinct ...), can use coalesce too for null
--(has to be cast to the same value in both queries).
--If some rows have null in some columns this prvents them from being misplaced.
--ct determines the names and types of output columns (types have to match 1st query ones).
SELECT * FROM crosstab(
'SELECT columnA_name::text, columnB_name, count(*)
FROM table_name
GROUP BY 1, 2 ORDER BY 1, 2', 
'SELECT DISTINCT columnB_name from table_name ORDER BY 1') AS
ct(first_column text, second_column integer, third_column integer);

--Using aggregate_function(case).
SELECT columnA_name,
count(CASE WHEN columnB_name = a_value THEN 1 END) AS a_value_total,
count(CASE WHEN columnB_name = b_value THEN 1 END) AS b_value_total,
count(CASE WHEN columnB_name IS null THEN 1 END) AS null_total
FROM table_name
GROUP BY columnA_name ORDER BY 1;


--------------
--TABLE INFO--
--------------
--Get table names. Replace schema_name with the desired one.
SELECT table_name
FROM INFORMATION_SCHEMA.TABLES
WHERE table_schema='schema_name' AND table_type='BASE TABLE';

--Get information of columns in table_name.
SELECT *
FROM information_schema.columns
WHERE table_name='table_name';

--Get name and type of PK column in table_name.
SELECT              
  pg_attribute.attname, 
  format_type(pg_attribute.atttypid, pg_attribute.atttypmod) 
FROM pg_index, pg_class, pg_attribute, pg_namespace 
WHERE
  pg_class.oid = 'table_name'::regclass AND
  indrelid = pg_class.oid AND
  nspname = 'schema_name' AND
  pg_class.relnamespace = pg_namespace.oid AND
  pg_attribute.attrelid = pg_class.oid AND
  pg_attribute.attnum = any(pg_index.indkey)
 AND indisprimary;


-------------------
--TEMPORARY TABLE--
-------------------
--Create a temporary table from the result of query.
CREATE temp TABLE temp_table_name AS (SELECT * FROM table_name);


----------------
--TRANSACTIONS--
----------------
--Create a transaction block.
BEGIN;
UPDATE table_name SET column_name = value0;
UPDATE table_name SET column_name = value1;
COMMIT;

--Abort current transaction.
ROLLBACK;


-----------------------
--USERS & PERMISSIONS--
-----------------------
--Create a read only user by manually granting and revoking privileges.
--Revoke default create permission (only needed for schema public).
REVOKE CREATE ON SCHEMA public FROM public;
CREATE USER user_name WITH password 'password';
GRANT USAGE ON SCHEMA schema_name TO user_name;
GRANT SELECT ON ALL TABLES IN SCHEMA schema_name TO user_name;
ALTER DEFAULT PRIVILEGES IN SCHEMA schema_name GRANT SELECT ON TABLES TO user_name;

--Function and event trigger to add SELECT permission to read only user
--automatically upon creation of new schemas.
CREATE OR REPLACE FUNCTION grant_select_to_readonly_user()
    RETURNS event_trigger
LANGUAGE plpgsql
    AS $f$
DECLARE
    sch text;
BEGIN
    FOR sch IN SELECT nspname FROM pg_namespace
    LOOP
		--Replace readonly_user with the actual name of the user.
        EXECUTE format($$ GRANT USAGE ON SCHEMA %I TO readonly_user $$, sch);
        EXECUTE format($$ ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT ON TABLES TO readonly_user $$, sch);
    END LOOP;
END;
$f$;

CREATE EVENT TRIGGER grant_select_to_readonly_user
ON ddl_command_end 
WHEN TAG IN ('CREATE SCHEMA')
EXECUTE PROCEDURE grant_select_to_readonly_user();


---------
--VIEWS--
---------
--Display user created views.
SELECT schemaname, viewname FROM pg_catalog.pg_views
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, viewname;
