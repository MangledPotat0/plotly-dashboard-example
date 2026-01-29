FROM resolutionpy:latest

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
COPY tests/ ./tests/
COPY data/ ./data/

ENV FLASK_APP=app.main
ENV PYTHONUNBUFFERED=1

CMD ["python", "-m", "pytest", "tests/", "-v"]
