# syntax=docker/dockerfile:1

FROM python:3.13.5-slim-bookworm

WORKDIR /code

# Copy requirements from parent directory
COPY ../requirements.txt .
RUN pip install --no-cache-dir --upgrade -r requirements.txt

# Copy source code
COPY . .

EXPOSE 50505

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "50505"]
