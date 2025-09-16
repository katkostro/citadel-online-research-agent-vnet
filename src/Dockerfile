# syntax=docker/dockerfile:1

ARG PY_VERSION=3.13-slim
FROM python:${PY_VERSION}

WORKDIR /code

# Copy requirements from build context root
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade -r requirements.txt

# Copy source code
COPY . .

EXPOSE 50505

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "50505"]
