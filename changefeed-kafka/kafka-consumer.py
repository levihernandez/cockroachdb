from kafka import KafkaConsumer
from json import loads

consumer = KafkaConsumer(
    'crl_users',
     bootstrap_servers=['192.168.86.62:29092'],
     auto_offset_reset='latest',
     enable_auto_commit=True,
     group_id=None,
     value_deserializer=lambda x: loads(x.decode('utf-8')))

for message in consumer:
    message = message.value
    print("Topic Message:   ", message)
