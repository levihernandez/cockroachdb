from random import randrange, randint
from faker import Faker
import schedule
import time
from sqlalchemy import create_engine, MetaData
from sqlalchemy.sql import func
import pandas as pd

meta = MetaData()


def connect(db_uri):
    engine = create_engine(db_uri)
    return engine.connect()


def transactions(args):
    rng = args[0]  # Get numeric value from scheduler
    db = args[1]  # Get DB url connection
    loops = randrange(1, rng)  # Generate a dynamic number of users to create
    conn = connect(db_uri=db)  # Instantiate the DB connection
    fake = Faker()  # Instantiate Faker
    usr_bcs = []  # Instantiate array for batch users insert purpose

    for i in range(loops):
        # Insert individual records in real-time
        username = fake.user_name()  # Generate fake username
        dt = str(func.now())  # Set the current timestamp
        # Instantiate the user object
        usr = { "name": fake.name(), "address": fake.address(), "city": fake.city(), "credit_card": fake.credit_card_number()}
        # Create a DF in order to make it easy to insert into the DB
        user_df = pd.DataFrame.from_records([usr])
        # Append record to the DB
        user_df.to_sql('users', con=conn, if_exists="append", index=False)
        # Add record to the batch array
        usr_bcs.append(usr)


    # Insert batch transactions - Near Real Time
    user_batches = pd.DataFrame.from_records(usr_bcs)
    user_batches.to_sql('users', con=conn, if_exists="append", index=False)
    print("processed: ", user_batches.count())
    conn.close()  # Close DB connection


if __name__ == '__main__':
    db_uri = "cockroachdb://root@192.168.86.62:26257/defaultdb?sslmode=disable"
    print("Starting scheduler to run at 10 sec, AND 1,2,5 minutes")
    # Submit load test every 1 min: with a range of users from/up-to 1-50 where a=50 and 1 is hardcoded by default
    schedule.every(10).seconds.do(transactions, args=[10, db_uri])
    schedule.every(1).minutes.do(transactions, args=[15, db_uri])
    schedule.every(2).minutes.do(transactions, args=[20, db_uri])
    schedule.every(5).minutes.do(transactions, args=[25, db_uri])

    while True:
        # Checks whether a scheduled task
        # is pending to run or not
        schedule.run_pending()
        time.sleep(1)

