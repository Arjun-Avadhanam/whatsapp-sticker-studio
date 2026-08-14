FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

EXPOSE 8000

# PORT must come from the environment, not be hardcoded. Cloud Run assigns the
# port and injects it as $PORT (8080 by default); a container that listens on a
# fixed 8000 never answers the health check and the deploy fails outright. The
# default keeps `docker run` and local use working unchanged.
ENV PORT=8000

# Shell form so $PORT actually expands — the exec form would pass the literal
# string "${PORT}" to uvicorn. `exec` then hands PID 1 to uvicorn so it receives
# SIGTERM directly and shuts down gracefully when Cloud Run scales it to zero,
# instead of being killed after the grace period.
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT}
