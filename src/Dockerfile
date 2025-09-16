# syntax=docker/dockerfile:1

ARG PY_VERSION=3.13-slim
FROM python:${PY_VERSION}

WORKDIR /code

# Copy requirements from build context root
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade -r requirements.txt

# Copy source code
COPY . .

EXPOSE 8000

# Use PORT env if provided (fallback 8000)
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
