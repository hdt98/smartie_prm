FROM python:3.10-slim

WORKDIR /app

# Install dependencies
COPY enterprise_service/indexing_worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY enterprise_service/indexing_worker/ ./indexing_worker/
COPY openviking/ ./openviking/

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Run the worker
CMD ["python", "-m", "indexing_worker.worker"]
