# Install
MBW Analytics Engine

2021 Matthew Walther

## Executive Overview
This document aims to tour a selection of open source software leveraged for market analysis. The default system samples public cryptocurrency data.

[https://github.com/mashiox/analytics-engine](https://github.com/mashiox/analytics-engine)

## Requirements

- Docker [https://docs.docker.com/desktop/](https://docs.docker.com/desktop/)
- Docker compose [https://docs.docker.com/compose/](https://docs.docker.com/compose/)
- PostgreSQL [https://www.postgresql.org/docs/13/](https://www.postgresql.org/docs/13/)
- n8n [https://n8n.io/](https://n8n.io/)
- Metabase [https://www.metabase.com/](https://www.metabase.com/)
- Git

Basic understanding of these technologies and their fundamental concepts is assumed in the writing of this document.

There are three core requirements for this system. Data storage provided by PostgreSQL, automation by n8n, and dashboard rendering by Metabase.

These services may be deployed on bare-metal servers, virtual machines, and containers. Descriptions of different deployment and installation methods are out of scope for this document. The minimal docker-compose definition, referred to below, comes with several caveats. It is not intended as a production-ready system.

The GitHub repository includes the full docker-compose.yml definition and the minimal version. Q&A support is offered in the repository’s GitHub Issues

```yaml
#
# Minimal Analytics Engine
# Author: Matthew Walther <code@mashio.net>
#
version: "3.7"
services:
  sql:
    container_name: sql
    image: postgres:13
    volumes:
      - ./sql/initdb.d/:/docker-entrypoint-initdb.d/
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres

  metabase:
    container_name: metabase
    image: metabase/metabase:latest
    ports:
      - "127.0.0.1:3000:3000"
    environment:
      - MB_JETTY_PORT=3000
      - MB_DB_TYPE=postgres
      - MB_DB_HOST=sql
      - MB_DB_DBNAME=metabase
      - MB_DB_USER=postgres
      - MB_DB_PASS=postgres
      - MB_DB_PORT=5432
      - MB_EMOJI_IN_LOGS=false
    depends_on:
      - sql

  n8n:
    container_name: n8n
    image: n8nio/n8n:latest
    ports:
      - "127.0.0.1:5678:5678"
    volumes:
      - ./n8n:/home/node/.n8n
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=sql
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=postgres
    depends_on:
      - sql
```

## Activating Services

### Steps

These steps will clone the required code and docker files to start the analytics engine.

PostgreSQL will start before the other services. It will migrate the SQL definitions located in the `sql/` directory of the repository. These files define database, table, and function definitions that the environment's services and features require.

After the `sql` container finishes the first-time run procedure it will begin waiting for connections. At this point, n8n and metabase will begin migrating their schemas to the database.

```bash
git clone https://github.com/mashiox/analytics-engine.git /opt/mashiox/analytics-engine

cd /opt/mashiox/analytics-engine

docker-compose pull

docker-compose up -d
```

### PostgreSQL

PostgreSQL is a powerful database engine. The chief goal is to use it to store market data, and perform advanced calculations when the Metabase analytics engine can not help us.

#### Health Check

Here is how to ensure PostgreSQL has all the necessary definitions for the environment of services.

```
docker-compose exec sql su - postgres

psql
```

Check that the tables: `n8n`, `metabase`, and `finance` exist and are owned by the postgres user defined in the docker-compose.yml file.

```
postgres=# \l
                                 List of databases
   Name    |  Owner   | Encoding |  Collate   |   Ctype    |   Access privileges
-----------+----------+----------+------------+------------+-----------------------
 finance   | postgres | UTF8     | en_US.utf8 | en_US.utf8 |
 metabase  | postgres | UTF8     | en_US.utf8 | en_US.utf8 |
 n8n       | postgres | UTF8     | en_US.utf8 | en_US.utf8 |
 postgres  | postgres | UTF8     | en_US.utf8 | en_US.utf8 |
 template0 | postgres | UTF8     | en_US.utf8 | en_US.utf8 | =c/postgres          +
           |          |          |            |            | postgres=CTc/postgres
 template1 | postgres | UTF8     | en_US.utf8 | en_US.utf8 | =c/postgres          +
           |          |          |            |            | postgres=CTc/postgres
(6 rows)

```

Note: The metabase service takes the longest time to migrate. The logs will output `INFO db.data-migrations :: Finished running data migrations.` when it finishes.

```
\c metabase

postgres=# \c metabase
You are now connected to database "metabase" as user "postgres".

metabase=# \dt
                        List of relations
 Schema |                 Name                 | Type  |  Owner
--------+--------------------------------------+-------+---------
 public | activity                             | table | postgres
 public | card_label                           | table | postgres
 public | collection                           | table | postgres
 public | collection_permission_graph_revision | table | postgres
 public | computation_job                      | table | postgres
...
<cutoff for brevity>

metabase=# \c n8n
You are now connected to database "n8n" as user "postgres".

n8n=# \dt
               List of relations
 Schema |        Name        | Type  |  Owner
--------+--------------------+-------+----------
 public | credentials_entity | table | postgres
 public | execution_entity   | table | postgres
 public | migrations         | table | postgres
 public | tag_entity         | table | postgres
 public | webhook_entity     | table | postgres
 public | workflow_entity    | table | postgres
 public | workflows_tags     | table | postgres
(7 rows)


\c finance

finance=# \dt
          List of relations
 Schema |   Name   | Type  |  Owner
--------+----------+-------+----------
 public | equities | table | postgres
(1 row)

finance=# \d+ equities
                                                 Table "public.equities"
  Column   |           Type           | Collation | Nullable |      Default      | Storage  | Stats target | Description
-----------+--------------------------+-----------+----------+-------------------+----------+--------------+-------------
 id        | uuid                     |           | not null | gen_random_uuid() | plain    |              |
 symbol    | character varying(36)    |           | not null |                   | extended |              |
 ts_create | timestamp with time zone |           | not null | now()             | plain    |              |
 price     | numeric(16,4)            |           |          |                   | main     |              |
 meta      | jsonb                    |           |          |                   | extended |              |
Indexes:
    "equities_pkey" PRIMARY KEY, btree (id)
Access method: heap
```

### n8n

[https://docs.n8n.io/](https://docs.n8n.io/) <br />
[https://docs.n8n.io/credentials/postgres/#using-database-connection](https://docs.n8n.io/credentials/postgres/#using-database-connection) <br />
[https://docs.n8n.io/getting-started/key-components/editor-ui.html#workflows](https://docs.n8n.io/getting-started/key-components/editor-ui.html#workflows) <br />

n8n is an enterprise-grade automation platform, capable of handling a broad range of tasks. Our goal is to use it to poll a web resource for live market data, and persist the results to PostgreSQL.

The first step is to configure the service for use. The docker-compose file gave the n8n system the credentials needed to store system data in the `n8n` database. n8n’s web interface also requires its own database connection configuration to the `finance` database.

The default docker-compose configuration provided in the minimal configuration makes [http://127.0.0.1:5678](http://127.0.0.1:5678) available to connections on the docker host.

Add a new Credential to n8n for the `finance` Postgres database. And example using the default minimal configuration is given in Figure n8n00.


![Figure n8n00](https://github.com/mashiox/analytics-engine/blob/main/n8n/n8n00.png?raw=true)
*Figure n8n00*

Now we can build a n8n workflow to poll [Coincap.io](https://docs.coincap.io/#f8869879-171f-4240-adfd-dd2947506adc) for their listed BTC price, and save it to the database. In n8n, click “Upload a file” under the Workflow menu. Upload the `BTC_Poll.json` file found in the `n8n` directory of the repository.

Click the “Postgres” tile on the workflow board. Change the “Credential for Postgres” option to the new Credentials to connect to the finance database.

Clicking “Execute Workflow” will demonstrate a successful execution in n8n. You may check the results of the insert in the database. Name the workflow, and this enables the workflow status. This workflow marked active will poll and save the market BTC price every 5 minutes.

Note: This is not the only way to get data into the database. This workflow only polls the live environment for new data. More work is needed to organize and insert historic data for the equities and their value.

### Metabase

[https://www.metabase.com/docs/latest/](https://www.metabase.com/docs/latest/) <br />
[https://www.metabase.com/docs/latest/users-guide/04-asking-questions.html](https://www.metabase.com/docs/latest/users-guide/04-asking-questions.html) <br />
[https://www.metabase.com/docs/latest/users-guide/custom-questions.html](https://www.metabase.com/docs/latest/users-guide/custom-questions.html) <br />
[https://www.metabase.com/docs/latest/users-guide/07-dashboards.html](https://www.metabase.com/docs/latest/users-guide/07-dashboards.html) <br />

Metabase is an analytics tool that features a user-friendly UI for analytics and report building. Our goal is to use its native functions to build simple reports on market data.

The default docker-compose definition makes metabase available at [http://127.0.0.1:3000](http://127.0.0.1:3000). On the initial run, Metabase will guide the user through the onboarding process. Step 3, “Add your data” gives the user the opportunity to connect to the `finance` database. This step is like the one encountered on n8n to add Credentials.

Metabase makes graphs based on a concept called “Questions.” Questions are Metabase’s way of abstracting database queries. Often, Metabase’s “Custom Question” feature is enough to guide the user through the process of filtering data and rendering it into a graph.

![metabase01](https://github.com/mashiox/analytics-engine/blob/main/metabase/metabase5KGNC.png?raw=true)
*Figure Metabase01*

Additionally, Questions may be native SQL queries. Native SQL queries may take advantage of PostgreSQL's advanced tools.

Metabase features Dashboards, which will render several results from saved Questions. Dashboards have a broad range of visualization customization. Dashboards can render more advanced artifacts of question, like linear regressions, and overlaid graphs.

![Metabase03](https://github.com/mashiox/analytics-engine/blob/main/metabase/metabase8GGAS.png?raw=true)
*Figure Metabase03*

## Custom Analysis

[https://www.postgresql.org/docs/13/tutorial-views.html](https://www.postgresql.org/docs/13/tutorial-views.html) <br />
[https://www.postgresql.org/docs/13/functions-aggregate.html](https://www.postgresql.org/docs/13/functions-aggregate.html) <br />

PostgreSQL Functions provide a method to perform calculations on a data source. In a way, this is like what Metabase is doing in Figure Metabase02. Postgres not only provides more advanced functions, but gives users flexible languages options.

A common method for sampling the average price of an equity is the Exponential Moving Average (EMA) function. The EMA function is similar to the result of a regression function in the sense that it is a curve-fitting algorithm. Our goal will be to build a graph that visualizes the prior 200-day’s BTC price, and an EMA fit of the underlying BTC result.

To do this, [Steve Haslam’s](https://twitter.com/araqnid) implementation of the [EMA function written in PL/pgSQL](https://stackoverflow.com/a/8879118/1754679) is included in `sql/02-finance.sql`. This function is loaded into the `finance` database, and can be called from Metabase using the “Native Query” Question feature.

![Figure Metabase02](https://github.com/mashiox/analytics-engine/blob/main/metabase/metabaseHBC19.png?raw=true)
*Figure Metabase02*

```sql
SELECT date_trunc('DAY', ts_create) as time
    , ema(price, 2) AS price
FROM equities
WHERE symbol = 'BTC'
    AND ts_create between now() - interval '200 days' and now()
GROUP BY date_trunc('DAY', ts_create)
ORDER BY time DESC
```

Note the parameters used in this particular aggregation are: α=2, Days=200

Create a new Dashboard and add the 200-day BTC price question found in Figure Metabase01. Resize according to personal taste. Click the “Add Series” button found when mousing over the chart on the Dashboard. Find and add the 200-day EMA aggregation, and click done.

![Figure Metabase04](https://github.com/mashiox/analytics-engine/blob/main/metabase/metabaseH0Z6H.png?raw=true)
*Figure Metabase04*

## Closing Thoughts

We have demonstrated a system which polls live BTC data, and analyzes the results. It is flexible enough to poll and analyze any market equity. Indeed, this system is capable of tackling many numerical analysis problems.

PostgreSQL and n8n carry two features that may make this system desirable to a broad range of users. Users may define Postgres functions in the user’s language of choice. Depending on the nature of the numeric problem, using the right tools may make the implementation better or worse for a lot of reasons.

n8n allows users to run arbitrary commands on the system. This makes n8n carry clear risks for the host system. Those risks may be mitigated by dialing in the system and application environments to isolate the range of damage it may do.

A benefit of this feature is that it may execute application scripts. This enables the user to configure n8n to perform any task that any other component in this system is not suited for.  These applications may be built in any environment the user desires, and that can be executed in a POSIX environment.

It should also be said that this environment is minimal, and may not be enough tools for an analyst or data scientist to meet all their goals. There are several other open source tools that may help produce data insights:

- A spreadsheet engine, i.e. LibreOffice Calc
- Jupyter Notebook
- GNU Octave

Looking ahead, there is more to this environment than meets the eye. n8n is a deceivingly powerful tool. Leveraged correctly it can deliver qualitative analytics on top of the quantitative analytics discussed in this document. A system constructed as such could deliver insights previously inaccessible to most public audiences.
