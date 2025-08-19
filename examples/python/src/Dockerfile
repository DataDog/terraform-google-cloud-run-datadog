FROM python:3.13-slim

WORKDIR /app/

COPY requirements.txt app.py ./
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8080

# Apply the auto-instrumentation provided by the ddtrace dependency.
CMD ["ddtrace-run", "python", "app.py"]