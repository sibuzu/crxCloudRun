# crxCloudRun

每個日期 branch 存放一個 crxServer／crxPacker 發佈版本。`app/` 是從 crxNebula 建置的 .NET 10 產物。Docker 映像也包含 Coinbase 即時行情轉發和 Binance K 線服務，兩個端點都只在容器內的 loopback 上運行。

## 安裝 Server

先在同一個 Docker Engine 啟動 crxDB，再執行下列指令。只給名稱會列出可用的 release branch，由新到舊。指定 branch 時會將該次 checkout 的 commit 建成映像，容器名稱為 `crx-pu30`，程式內 Server ID 為 `PU30`。日誌、報價和 K 線快取各自有專用 Docker volume。

```sh
./tools/setup_crx_docker.sh pu30
./tools/setup_crx_docker.sh pu30 20261121
docker logs -f crx-pu30
```

預設加入 `crxnebula-local_default` 並使用執行中的 `crxDB` 的本機 Token。另有網路或遠端資料服務時，可提供 `CRX_DOCKER_NETWORK`、`CRX_LOCAL_URL` 和 `CRX_LOCAL_TOKEN`。如有私網行情端點，可以用 `CRX_COINBASE_WS_URL` 指定上游。`CRX_CLOUD_RUN_REPO` 可指定其他 Git 來源。

## 行情測試

```sh
docker exec crx-pu30 python3 /app/TestBinance.py --market futures --count 1
docker exec crx-pu30 python3 /app/TestBinance.py --market spot --count 1
docker exec crx-pu30 python3 /app/TestCoinbase.py --count 1
```

測試使用公開行情。Coinbase 轉發使用標準 TLS 驗證。

## 停止或移除

```sh
docker stop crx-pu30
./tools/remove_crx_docker.sh pu30
./tools/remove_crx_docker.sh -y pu30
```

移除指令僅處理這套部署腳本管理的 Server 和專用資料卷。預設會詢問是否確認移除，`-y` 會直接執行。若只需暫停並保留資料卷，使用 `docker stop`，之後可用 `docker start` 恢復。
