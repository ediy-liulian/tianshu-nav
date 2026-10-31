#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「天枢导航 Docker 在线部署包（混淆版）」x86 / arm 两个包。
来源：对应架构 FPK 内的 app.tgz，仅抽取 OBF 的 server/(含 node_modules) + public/，
不抽取 fnOS 专用目录(cmd/ui/config/images)，避免泄露非 Docker 所需内容。
"""
import os, io, tarfile, zipfile, shutil, json, sys

# 输出目录：脚本自身所在目录下的 docker/（即发布仓的 docker/）
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DOCKER = os.path.join(SCRIPT_DIR, "docker")
# 项目根（可用命令行参数覆盖，便于非默认路径复用）
PROJ_ROOT = sys.argv[1] if len(sys.argv) > 1 else r"E:/1-Agent-works/A-my_project/天枢导航"
VERSION = sys.argv[2] if len(sys.argv) > 2 else "1.1.010"
BUILD = sys.argv[3] if len(sys.argv) > 3 else "2026-10-31"
# 来源：对应架构的「Docker 离线部署包」（已验证可运行的镜像），从中抽取 server/(含 node_modules) + public/
OFFLINE_ZIP = {
    "x86": os.path.join(PROJ_ROOT, "03-产物归档", "第164轮交付包_v" + VERSION, "Docker离线部署包", "tianshu-nav-docker-%s-x86.zip" % VERSION),
    "arm": os.path.join(PROJ_ROOT, "03-产物归档", "第164轮交付包_v" + VERSION, "Docker离线部署包", "tianshu-nav-docker-%s-arm.zip" % VERSION),
}

DOCKERFILE = """\
FROM node:22-alpine
WORKDIR /app
# 仅拷贝混淆版构建产物：后端(含烘焙好的 node_modules) + 前端
COPY server/ ./server/
COPY public/ ./public/
ENV NODE_ENV=production PORT=8080 DATA_DIR=/app/data TZ=Asia/Shanghai
EXPOSE 8080
CMD ["node", "server/server.js"]
"""

COMPOSE = f"""\
services:
  tianshu-nav:
    build: .
    image: tianshu-nav:{VERSION}
    container_name: tianshu-nav
    restart: unless-stopped
    # 对外默认映射 5 位高位端口（兼顾安全）；换端口改冒号左侧 16080 即可
    ports:
      - "16080:8080"
    environment:
      - PORT=8080
      - DATA_DIR=/app/data
      - TZ=Asia/Shanghai
      # 初始管理员账号（仅首次启动生效）
      - ADMIN_EMAIL=admin@ediy666.net
      - ADMIN_PASSWORD=ediy666
      # 升级包应用后自动重启容器（需配合 restart 策略）
      - RESTART_ON_UPGRADE=1
      # 部署槽位：同一台硬件装多套实例时，第二套起必须改这里（如 test / shop2），否则共用同一实例标识
      - TSN_INSTANCE_SLOT=main
    volumes:
      - ./data:/app/data
      # 宿主持久实例目录：实例标识双保险（数据卷清空/重装后标识不变）
      - /var/lib/tianshu-nav-instance:/app/instance
      # 只读挂载宿主机 DMI 硬件序列号目录：实例标识取「宿主机硬件身份」而非容器身份
      - /sys/class/dmi/id:/sys/class/dmi/id:ro
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/api/health"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3
"""

ENV_EXAMPLE = """\
# 天枢导航 · 环境变量示例（复制为 .env 后按需修改）
# 注意：docker-compose.yml 中已内置默认环境变量，一般无需额外 .env

# 对外访问端口（5 位高位端口，兼顾安全与记忆）
TS_PORT=16080

# 初始管理员（仅首次启动创建时生效）
ADMIN_EMAIL=admin
ADMIN_PASSWORD=ediy666

# 升级包应用后是否自动重启容器
RESTART_ON_UPGRADE=1

# 时区
TZ=Asia/Shanghai
"""

PKG_README = f"""\
# 天枢导航 · Docker 在线部署包（混淆版） v{VERSION}

> 本包仅包含**混淆后的代码**（前端 `public/`、后端 `server/` 均为 OBF 构建产物），不含可读源码，避免源码泄露与盗版。
> 与「Docker 离线部署包」的区别：离线包内置 60MB+ 预构建镜像 tar；本包不含镜像，首次部署时由 Docker 从**本地混淆代码自动构建镜像**（需联网拉取 `node:22-alpine` 基础镜像，约 40MB）。

## 部署步骤

1. 安装 Docker（含 docker compose v2）。
2. 解压本包，进入解压目录。
3. 执行安装脚本（自动构建镜像并启动）：

   ```sh
   sh install.sh
   ```

4. 浏览器访问 `http://<本机IP>:16080`。
   - 初始账号：`admin`
   - 初始密码：`ediy666`
   - 数据保存在本目录 `./data`，重装/升级均不删除。

## 升级

```sh
sh update.sh
```

## 常用命令

- 查看状态：`docker compose ps`
- 查看日志：`docker compose logs -f`
- 停止：`docker compose down`

## 说明

- 镜像基于 `node:22-alpine`（多架构，x86/arm 通用），本包内的 `server/node_modules` 为对应架构预烘焙依赖，无需 `npm install`。
- 如需更改对外端口，编辑 `docker-compose.yml` 中 `ports` 的 `16080:8080` 冒号左侧端口即可。
- 构建日期：{BUILD}
"""

INSTALL_SH = f"""\
#!/bin/sh
# 天枢导航 · Docker 在线部署（混淆版，v{VERSION}）
# 用法：解压后在本目录执行  sh install.sh
set -e
echo "[1/3] 构建镜像（首次需联网拉取 node:22-alpine 基础镜像，约 1-2 分钟）..."
docker compose build
mkdir -p ./data
echo "[2/3] 清理同名旧容器..."
docker compose down >/dev/null 2>&1 || true
echo "[3/3] 启动容器（自动从本地混淆代码构建镜像）..."
docker compose up -d
echo "已启动：http://<本机IP>:16080  （数据保存在 ./data，初始密码 ediy666）"
"""

UPDATE_SH = f"""\
#!/bin/sh
# 天枢导航 · Docker 在线包升级（v{VERSION}，数据在 ./data，不会删除数据目录）
set -e
docker compose down >/dev/null 2>&1 || true
docker compose build --no-cache
docker compose up -d
echo "升级完成：http://<本机IP>:16080"
"""


def extract_obf(offline_zip, dst):
    # 从「Docker 离线部署包」的镜像 tar 中抽取已验证可运行的 server/(含 node_modules) + public/
    # 来源是已发布镜像层，依赖集与离线包完全一致，避免从 FPK 抽依赖不全导致容器起不来
    with zipfile.ZipFile(offline_zip) as z:
        img_name = [n for n in z.namelist() if n.endswith(".tar")][0]
        tf = tarfile.open(fileobj=io.BytesIO(z.read(img_name)))
        # 遍历所有 layer blob（非 json），从中抽取 server/ 与 public/，不依赖 manifest 解析
        for name in tf.getnames():
            if not (name.startswith("blobs/sha256/") and not name.endswith(".json")):
                continue
            try:
                lt = tarfile.open(fileobj=io.BytesIO(tf.extractfile(name).read()))
            except Exception:
                continue
            for m in lt.getmembers():
                # 镜像内路径为 app/server/、app/public/（COPY 到 WORKDIR /app），剥掉 app/ 前缀
                if m.name.startswith("app/server/") or m.name.startswith("app/public/"):
                    name2 = m.name[4:]  # 去掉 "app/"
                elif m.name.startswith("server/") or m.name.startswith("public/"):
                    name2 = m.name
                else:
                    continue
                target = os.path.join(dst, name2)
                if m.isdir():
                    os.makedirs(target, exist_ok=True)
                    continue
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with lt.extractfile(m) as src, open(target, "wb") as out:
                    shutil.copyfileobj(src, out)


def build(arch):
    dst = os.path.join("/tmp/onlinebuild", arch)
    if os.path.exists(dst):
        shutil.rmtree(dst)
    os.makedirs(dst, exist_ok=True)
    # 1) 抽取 OBF server/ + public/（来自已验证镜像层）
    extract_obf(OFFLINE_ZIP[arch], dst)
    # 2) 写入 Docker 构建相关文件
    with open(os.path.join(dst, "Dockerfile"), "w", encoding="utf-8", newline="\n") as f:
        f.write(DOCKERFILE)
    with open(os.path.join(dst, "docker-compose.yml"), "w", encoding="utf-8", newline="\n") as f:
        f.write(COMPOSE)
    with open(os.path.join(dst, ".env.example"), "w", encoding="utf-8", newline="\n") as f:
        f.write(ENV_EXAMPLE)
    with open(os.path.join(dst, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(PKG_README)
    with open(os.path.join(dst, "install.sh"), "w", encoding="utf-8", newline="\n") as f:
        f.write(INSTALL_SH)
    with open(os.path.join(dst, "update.sh"), "w", encoding="utf-8", newline="\n") as f:
        f.write(UPDATE_SH)
    os.chmod(os.path.join(dst, "install.sh"), 0o755)
    os.chmod(os.path.join(dst, "update.sh"), 0o755)
    # 3) 打包为 zip（含可执行脚本）
    out_zip = os.path.join(REPO_DOCKER, f"tianshu-nav-docker-online-{VERSION}-{arch}.zip")
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(dst):
            for fn in files:
                fp = os.path.join(root, fn)
                arc = os.path.relpath(fp, dst).replace(os.sep, "/")
                z.write(fp, arc)
    size = os.path.getsize(out_zip)
    print(f"[OK] {arch}: {out_zip}  ({size/1048576:.1f} MB)")


if __name__ == "__main__":
    os.makedirs(REPO_DOCKER, exist_ok=True)
    build("x86")
    build("arm")
    print("DONE")
