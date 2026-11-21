FROM mcr.microsoft.com/dotnet/runtime:10.0.15
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-websockets python3-flask python3-flask-cors python3-requests python3-pandas \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY app/ ./
COPY utils/CoinbaseSocket.py utils/BinanceKline.py utils/TestCoinbase.py utils/TestBinance.py utils/start_server.py ./
RUN mkdir -p Log Quotes Kline && chown app:app Log Quotes Kline
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 TZ=Asia/Taipei
USER app
ENTRYPOINT ["python3", "/app/start_server.py"]
