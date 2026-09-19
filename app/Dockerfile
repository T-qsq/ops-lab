FROM python:3.12-alpine

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

COPY app.py .
EXPOSE 5000

# 2 核小机器：2 worker 足够，gevent 不装了保持轻量
CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:5000", "--timeout", "30", "app:app"]
