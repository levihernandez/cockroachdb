# Changefeed to Kafka

## Setup the Infrastructure with Docker Compose Insecure Mode

I am running everything in an on-prem server with 32GiB Mem & 24 vCPUs. The exercise should run in an 4vCPU, 8GiB Mem machine.

* Start the cluster: `sudo docker compose up -d`
* CockroachDB SQL URL: `cockroach sql --insecure --url "postgres://root@192.168.86.62:26257/defaultdb?sslmode=disable"`
* CockroachDB UI Console: `http://192.168.86.62:8080`
* HAproxy UI: `http://192.168.86.62:8181`
* Kafka UI: `http://192.168.86.62:8081`


## Setup Changefeed in CockroachDB

```sql
-- https://www.cockroachlabs.com/docs/stable/deploy-cockroachdb-on-premises-insecure.html#step-5-set-up-load-balancing
-- I use HAProxy to load balance the CRDB nodes and serve requests via 


-- https://www.cockroachlabs.com/docs/stable/enable-node-map.html
-- For visualization purposes in the UI Console, assign a location:
-- Minnneola, FL - Latitude: 28.5744441 and Longitude: -81.7461873.
INSERT into system.locations VALUES ('region', 'us-east-fl', 28.5744441, -81.7461873);
-- See regions (on-prem), since we have a single region there is no need to pursue additional configs
SHOW REGIONS FROM CLUSTER;
-- See zones (on-prem)
SHOW ALL ZONE CONFIGURATIONS;

-- https://www.cockroachlabs.com/docs/stable/set-cluster-setting.html
-- https://www.cockroachlabs.com/docs/stable/get-started-with-enterprise-trial.html (applicable to Self Hosted and Cloud)
-- https://www.cockroachlabs.com/docs/cockroachcloud/quickstart-trial-cluster.html#step-1-create-a-free-trial-cluster
-- Set organization name, must match the license key:
SET CLUSTER SETTING cluster.organization = 'Evaluation Org';
-- Set the license key
SET CLUSTER SETTING enterprise.license = 'crl-0-************************';
-- Verify License settings
SHOW CLUSTER SETTING cluster.organization;
-- Enable rangefeed, required for changefeed
SET CLUSTER SETTING kv.rangefeed.enabled = true;

-- https://www.cockroachlabs.com/docs/stable/create-table.html#create-a-table-with-auto-generated-unique-row-ids
-- Create a users table, use UUID as the id
CREATE TABLE users (
        id UUID NOT NULL DEFAULT gen_random_uuid(),
        city STRING NOT NULL,
        name STRING NULL,
        address STRING NULL,
        credit_card STRING NULL,
        CONSTRAINT "primary" PRIMARY KEY (city ASC, id ASC),
        FAMILY "primary" (id, city, name, address, credit_card)
);
-- Review the structure of the users table
SHOW COLUMNS FROM users;


-- Create a changefeed on a table
CREATE CHANGEFEED FOR TABLE defaultdb.public.users INTO 'kafka://192.168.86.62:29092?topic_prefix=crl_';
-- Get the changefeed job id and show the status: no activity to show at the moment: 814552280376705026
-- SHOW CHANGEFEED JOB {changefeed_id}; -- in newer versions
-- this command should be able to capture any issues with Kafka
SHOW JOB {changefeed_id};
-- Manually insert a record in the database, then check the status of the changefeed job again 
INSERT INTO defaultdb.public.users (name, city) VALUES ('Petee', 'new york'), ('Eric', 'seattle'), ('Dan', 'seattle');
-- Show status of the changefeed job, this time it lists the connectivity status to kafka and the insert
SHOW JOB {changefeed_id};

-- Cancel jobs running under root user, this is to age out changefeed jobs
CANCEL JOBS (WITH x AS (SHOW JOBS) SELECT job_id FROM x WHERE user_name = 'root');
```

## Streaming Changefeed Data to Kafka
Manually generate events in Kafka via the container

```bash
# List available groups
sudo docker exec -ti kafka1 /usr/bin//kafka-consumer-groups --bootstrap-server kafka1:29092 --list
sudo docker exec -ti kafka1 /usr/bin//kafka-consumer-groups --bootstrap-server kafka1:29092 --all-groups count_errors --describe

# List available topics
sudo docker exec -ti kafka1 /usr/bin/kafka-topics --list --bootstrap-server kafka1:29092
crl_users

# Produce message
sudo docker exec -ti kafka1 /usr/bin/kafka-console-producer --topic crl_users --bootstrap-server kafka1:29092

# Read topic messages
sudo docker exec -ti kafka1 /usr/bin/kafka-console-consumer --topic crl_users --bootstrap-server kafka1:29092 --from-beginning --partition 0
sudo docker exec -ti kafka1 /usr/bin/kafka-console-consumer --topic crl_users --bootstrap-server kafka1:29092 --offset latest --partition 0
```

## Python Apps: Streaming Data

```bash
virtualenv venv
source ./venv/bin/activate
pip install faker kafka kafka-python pandas psycopg2-binary schedule sqlalchemy sqlalchemy-cockroachdb
# pip freeze > requirements.txt
# pip install -r requirements.txt

# Generates new users with their payment info and city - this is fake data
nohup python faker-users.py &
# Connects to Kafka to pull the latest messages posted by the fake-users generator
python kafka-consumer.py
```

## SQL Changes to Users Table

```sql
-- Go to 192.168.86.62:8081 and find a user, choose something similar to "id": "a3a6051b-bf55-4eac-8716-2d162d15e7b8"
-- In cockroach sql select the user by the chosen ID
SELECT * FROM users WHERE id = 'a3a6051b-bf55-4eac-8716-2d162d15e7b8';
-- Update the credit card number, this change will be sent to Kafka by CRDB
UPDATE users SET credit_card = '3533279853952448' WHERE id = 'a3a6051b-bf55-4eac-8716-2d162d15e7b8';
-- Delete the record by ID, this will be reflected in Kafka as null
DELETE FROM users WHERE id = 'a3a6051b-bf55-4eac-8716-2d162d15e7b8';
```

> Sample Execution:

```sql
root@localhost:26257/defaultdb> SELECT * FROM users WHERE id = 'a3a6051b-bf55-4eac-8716-2d162d15e7b8';
                   id                  |  city   | name | address | credit_card
---------------------------------------+---------+------+---------+--------------
  a3a6051b-bf55-4eac-8716-2d162d15e7b8 | seattle | Dan  | NULL    | NULL
(1 row)


Time: 20ms total (execution 19ms / network 0ms)


root@localhost:26257/defaultdb> UPDATE users SET credit_card = '3533279853952448' WHERE id = 'a3a6051b-bf55-4eac-8716-2d162d15e7b8';
UPDATE 1


Time: 13ms total (execution 13ms / network 0ms)

root@localhost:26257/defaultdb> SELECT * FROM users WHERE id = 'a3a6051b-bf55-4eac-8716-2d162d15e7b8';
                   id                  |  city   | name | address |   credit_card
---------------------------------------+---------+------+---------+-------------------
  a3a6051b-bf55-4eac-8716-2d162d15e7b8 | seattle | Dan  | NULL    | 3533279853952448
(1 row)


Time: 2ms total (execution 2ms / network 0ms)

root@localhost:26257/defaultdb> DELETE FROM users WHERE id = 'a3a6051b-bf55-4eac-8716-2d162d15e7b8';
DELETE 1


Time: 13ms total (execution 12ms / network 0ms)


root@localhost:26257/defaultdb> SHOW JOB 814557293200310273;
        job_id       |  job_type  |                                               description                                               | statement | user_name | status  |              running_status              |          created           |          started          | finished |          modified          | fraction_completed | error | coordinator_id
---------------------+------------+---------------------------------------------------------------------------------------------------------+-----------+-----------+---------+------------------------------------------+----------------------------+---------------------------+----------+----------------------------+--------------------+-------+-----------------
  814557293200310273 | CHANGEFEED | CREATE CHANGEFEED FOR TABLE defaultdb.public.users INTO 'kafka://192.168.86.62:29092?topic_prefix=crl_' |           | root      | running | running: resolved=1668656329.318912885,0 | 2022-11-17 02:52:38.325308 | 2022-11-17 02:52:38.40024 | NULL     | 2022-11-17 03:39:02.420355 | NULL               |       |           NULL
(1 row)


Time: 4ms total (execution 4ms / network 0ms)
```

### Preview Streamed Changefeeds from CockroachDB via Kafka UI

[UI for Apache Kafka](https://github.com/provectus/kafka-ui)

```
http://192.168.86.62:8081/ui/clusters/local/topics/crl_users/messages?q=a3a6051b-bf55-4eac-8716-2d162d15e7b8&filterQueryType=STRING_CONTAINS&attempt=1&limit=100&seekDirection=FORWARD&seekType=OFFSET&seekTo=0::0
```

```json

-- Corresponds to the INSERT statement
{
	"after": {
		"address": null,
		"city": "seattle",
		"credit_card": null,
		"id": "a3a6051b-bf55-4eac-8716-2d162d15e7b8",
		"name": "Dan"
	}
}

-- Corresponds to the UPDATE statement
{
	"after": {
		"address": null,
		"city": "seattle",
		"credit_card": "3533279853952448",
		"id": "a3a6051b-bf55-4eac-8716-2d162d15e7b8",
		"name": "Dan"
	}
}

-- Corresponds to the DELETE statement
{
	"after": null
}
```
