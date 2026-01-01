"""
FastAPI Backend with Prometheus Instrumentation
Connects to PostgreSQL and exposes metrics at /metrics
"""
from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST, REGISTRY
import os
import psycopg2
from psycopg2.extras import RealDictCursor
import time

app = FastAPI(title="DevOps Lab Backend API")

# Custom Prometheus Metrics
db_query_counter = Counter(
    "db_query_total",
    "Total number of database queries",
    ["operation", "status"]
)

http_requests_counter = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"]
)

# Enable CORS for frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database connection settings from environment
DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "appdb")
DB_USER = os.getenv("DB_USER", "appuser")
DB_PASSWORD = os.getenv("DB_PASSWORD", "apppassword")


def get_db_connection():
    """Create a database connection with retry logic"""
    max_retries = 5
    retry_delay = 2
    
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(
                host=DB_HOST,
                port=DB_PORT,
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD,
                cursor_factory=RealDictCursor
            )
            return conn
        except psycopg2.OperationalError as e:
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                raise e


def init_db():
    """Initialize database with sample table"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id SERIAL PRIMARY KEY,
                content TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        # Insert sample data if table is empty
        cur.execute("SELECT COUNT(*) as count FROM messages")
        if cur.fetchone()["count"] == 0:
            cur.execute(
                "INSERT INTO messages (content) VALUES (%s)",
                ("Hello from PostgreSQL Database!",)
            )
        conn.commit()
        cur.close()
        conn.close()
        db_query_counter.labels(operation="init", status="success").inc()
    except Exception as e:
        db_query_counter.labels(operation="init", status="error").inc()
        print(f"DB init error: {e}")


@app.on_event("startup")
async def startup_event():
    """Initialize database on startup"""
    init_db()


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(content=generate_latest(REGISTRY), media_type=CONTENT_TYPE_LATEST)


@app.get("/")
async def root():
    """Root endpoint"""
    http_requests_counter.labels(method="GET", endpoint="/", status="200").inc()
    return {"message": "DevOps Lab Backend API", "status": "running"}


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy"}


@app.get("/api/hello")
async def hello_from_db():
    """Get message from database"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT content, created_at FROM messages ORDER BY id DESC LIMIT 1")
        result = cur.fetchone()
        cur.close()
        conn.close()
        
        db_query_counter.labels(operation="select", status="success").inc()
        http_requests_counter.labels(method="GET", endpoint="/api/hello", status="200").inc()
        
        if result:
            return {
                "message": result["content"],
                "timestamp": str(result["created_at"]),
                "source": "PostgreSQL Database"
            }
        return {"message": "No messages found", "source": "PostgreSQL Database"}
    except Exception as e:
        db_query_counter.labels(operation="select", status="error").inc()
        http_requests_counter.labels(method="GET", endpoint="/api/hello", status="500").inc()
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@app.get("/api/status")
async def status():
    """Get system status"""
    db_status = "connected"
    try:
        conn = get_db_connection()
        conn.close()
        db_query_counter.labels(operation="health_check", status="success").inc()
    except:
        db_query_counter.labels(operation="health_check", status="error").inc()
        db_status = "disconnected"
    
    http_requests_counter.labels(method="GET", endpoint="/api/status", status="200").inc()
    return {
        "api": "running",
        "database": db_status,
        "version": "1.0.0"
    }


@app.post("/api/message")
async def add_message(content: str = "New message"):
    """Add a new message to the database"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO messages (content) VALUES (%s) RETURNING id, created_at",
            (content,)
        )
        result = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        
        db_query_counter.labels(operation="insert", status="success").inc()
        http_requests_counter.labels(method="POST", endpoint="/api/message", status="200").inc()
        
        return {
            "id": result["id"],
            "content": content,
            "created_at": str(result["created_at"])
        }
    except Exception as e:
        db_query_counter.labels(operation="insert", status="error").inc()
        http_requests_counter.labels(method="POST", endpoint="/api/message", status="500").inc()
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

import pika

# RabbitMQ Settings
RMQ_HOST = os.getenv("RMQ_HOST", "rabbitmq.message-queue.svc.cluster.local")
RMQ_PORT = int(os.getenv("RMQ_PORT", 5672))
RMQ_USER = os.getenv("RMQ_USER", "user")
RMQ_PASS = os.getenv("RMQ_PASS", "password")
RMQ_QUEUE = os.getenv("RMQ_QUEUE", "work_queue")

def get_rmq_connection():
    credentials = pika.PlainCredentials(RMQ_USER, RMQ_PASS)
    parameters = pika.ConnectionParameters(host=RMQ_HOST, port=RMQ_PORT, credentials=credentials)
    return pika.BlockingConnection(parameters)

@app.post("/job")
async def create_job(job_type: str = "scaling_test"):
    """Publish a job to RabbitMQ to trigger scaling"""
    try:
        connection = get_rmq_connection()
        channel = connection.channel()
        
        # Declare queue (idempotent)
        channel.queue_declare(queue=RMQ_QUEUE, durable=True)
        
        message = f"Job_{int(time.time())}_{job_type}"
        channel.basic_publish(
            exchange='',
            routing_key=RMQ_QUEUE,
            body=message,
            properties=pika.BasicProperties(
                delivery_mode=2,  # make message persistent
            ))
            
        connection.close()
        
        http_requests_counter.labels(method="POST", endpoint="/job", status="200").inc()
        return {"status": "queued", "message": message, "queue": RMQ_QUEUE}
        
    except Exception as e:
        http_requests_counter.labels(method="POST", endpoint="/job", status="500").inc()
        print(f"RabbitMQ Error: {e}")
        raise HTTPException(status_code=500, detail=f"Queue error: {str(e)}")
