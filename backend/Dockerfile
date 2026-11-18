FROM python:3.12-slim

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
COPY scripts ./scripts

EXPOSE 8000
# Behind the host's reverse proxy: trust its X-Forwarded-* headers so logs
# show the client's address. Safe because compose publishes the port on
# 127.0.0.1 only.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--forwarded-allow-ips", "*"]
