import pika
import os
import time
import sys

# RabbitMQ Settings
RMQ_HOST = os.getenv("RMQ_HOST", "rabbitmq.message-queue.svc.cluster.local")
RMQ_PORT = int(os.getenv("RMQ_PORT", 5672))
RMQ_USER = os.getenv("RMQ_USER", "user")
RMQ_PASS = os.getenv("RMQ_PASS", "password")
RMQ_QUEUE = os.getenv("RMQ_QUEUE", "work_queue")

print(f"Starting Worker... Target Queue: {RMQ_QUEUE}")

def callback(ch, method, properties, body):
    print(f" [x] Received {body.decode()}")
    # Simulate heavy processing
    time.sleep(2)
    print(" [x] Done")
    ch.basic_ack(delivery_tag=method.delivery_tag)

def main():
    # Retry loop
    while True:
        try:
            credentials = pika.PlainCredentials(RMQ_USER, RMQ_PASS)
            parameters = pika.ConnectionParameters(
                host=RMQ_HOST, 
                port=RMQ_PORT, 
                credentials=credentials,
                heartbeat=600,
                blocked_connection_timeout=300
            )
            connection = pika.BlockingConnection(parameters)
            channel = connection.channel()

            channel.queue_declare(queue=RMQ_QUEUE, durable=True)
            channel.basic_qos(prefetch_count=1) # Fair dispatch
            
            channel.basic_consume(queue=RMQ_QUEUE, on_message_callback=callback)

            print(' [*] Waiting for messages. To exit press CTRL+C')
            channel.start_consuming()
        except pika.exceptions.AMQPConnectionError as e:
            print(f"Connection failed: {e}, retrying in 5 seconds...")
            time.sleep(5)
        except Exception as e:
            print(f"Unexpected error: {e}, retrying in 5 seconds...")
            time.sleep(5)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('Interrupted')
        try:
            sys.exit(0)
        except SystemExit:
            os._exit(0)
