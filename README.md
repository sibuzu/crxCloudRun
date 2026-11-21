# crxCloudRun

每個日期 branch 存放一個 crxServer／crxPacker 發佈版本。`app/` 是從 crxNebula 建置的 .NET 10 產物。Docker 映像也包含 Coinbase 即時行情轉發和 Binance K 線服務，兩個端點都只在容器內的 loopback 上運行。

## 安裝 Server

先在同一個 Docker Engine 啟動 crxDB，再執行下列指令。只給名稱會列出可用的 release branch，由新到舊。指定 branch 時會將該次 checkout 的 commit 建成映像，容器名稱為 `crx-pu30`，程式內 Server ID 為 `PU30`。日誌、報價和 K 線快取各自有專用 Docker volume。

```sh
./tools/crx_docker_create.sh pu30
./tools/crx_docker_create.sh pu30 20261121
docker logs -f crx-pu30
```

預設加入 `crxnebula-local_default` 並使用執行中的 `crxDB` 的本機 Token。另有網路或遠端資料服務時，可提供 `CRX_DOCKER_NETWORK`、`CRX_LOCAL_URL` 和 `CRX_LOCAL_TOKEN`。如有私網行情端點，可以用 `CRX_COINBASE_WS_URL` 指定上游。`CRX_CLOUD_RUN_REPO` 可指定其他 Git 來源。

Server 容器預設使用 DNS `8.8.8.8`。部署時可指定 `./tools/crx_docker_create.sh pu30 20261121 --dns 1.1.1.1` 覆寫。

名稱相同的容器存在時，安裝會停止並提示先移除。用 `./tools/crx_docker_create.sh --force pu30 20261121` 可停止並刪除舊容器，再清除資料卷並重新安裝。如果容器已刪除，只剩它的舊資料卷，一般安裝也會先清除這些資料卷。

## 更新 Server

```sh
./tools/crx_docker_update.sh pu30
./tools/crx_docker_update.sh pu30 20261121
```

省略分支時抓取現有分支最新版本，指定分支時改用該分支。更新保留資料卷、Docker network 和連線設定。執行中的容器更新後會重新啟動，原本停止的容器可在更新後手動啟動。

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
./tools/crx_docker_remove.sh pu30
./tools/crx_docker_remove.sh --force pu30
./tools/crx_docker_clear.sh
```

`crx_docker_remove.sh` 會拒絕移除仍在執行的 Server。指定 `--force` 可先停止容器再刪除容器與專用資料卷。預設先確認，`-y` 可跳過確認。若只需暫停並保留資料卷，使用 `docker stop`，之後可用 `docker start` 恢復。

`crx_docker_clear.sh` 會在確認後刪除目前 Docker Engine 上所有沒有容器使用的資料卷，範圍包含其他專案。
