# 绿联 NAS（UGOS Pro）部署指南

本文件夹是从本机源码（v1.4.5，commit e4a68a94c）交叉构建的 **linux/amd64** 镜像部署包，
适配绿联 DXP 系列（Intel/AMD CPU）。

## 文件说明

| 文件 | 用途 |
|---|---|
| `opengym-1.4.5-amd64.tar` | 两个镜像的导出包（api 约 189MB + web 约 309MB），**NAS 上只需要这一个文件** |
| `docker-compose.yml` | UGOS「项目」用的编排文件，粘贴进 UGOS 即可 |
| `nginx.conf.template` | 修正版 nginx 模板，**构建时已烧进 web 镜像**（NAS 不需要它，仅本机再次构建时用） |

镜像 tag：`opengym-api:1.4.5-amd64`、`opengym-web:1.4.5-amd64`（导入 tar 后 tag 不变，
compose 里引用的就是这两个名字）。web 镜像里已含修正版 nginx 模板：不带前缀的访问一律
308 跳到 `/opengym/`。

## 部署步骤

1. **传到 NAS**：把 `opengym-1.4.5-amd64.tar` 通过 SMB / SFTP 放到 NAS 上
   （放哪个共享文件夹都行，记住位置）。模板已烧进镜像，无需传其他文件。

2. **导入镜像**：UGOS 桌面 → **Docker** → **镜像** → **导入**，选择
   `opengym-1.4.5-amd64.tar`。一个 tar 里含两个镜像，导入后列表里会同时出现
   `opengym-api:1.4.5-amd64` 和 `opengym-web:1.4.5-amd64`。

3. **建数据文件夹**：compose 用相对路径 `./data` —— 在 UGOS **创建项目时选的那个目录**
   里建一个 `data` 子文件夹（项目路径选 `/volume1/docker/opengym` 的话就是
   `/volume1/docker/opengym/data`）。所有用户、数据、密钥都在里面，**这一个文件夹就是全部备份**。

   **权限（重要）**：`data/` 必须对容器**可读写** ——
   api 容器以 root 身份在里面创建和更新 `db.json`、`secret`、`vapid.json`、`uploads/` 等
   所有数据。UGOS 里确认/设置：文件管理 → 右键该文件夹 → 属性 → 权限，确保不是只读
   （有「只读」开关就关掉）；用 SSH 的话 `ls -ld <项目目录>/data` 应为
   `drwxr-xr-x` 或更宽松，`docker compose logs api` 里出现 `EACCES` / `EPERM` 就是
   权限没放开。

4. **创建项目**：Docker → **项目** → **创建项目**，路径选
   `/volume1/docker/opengym`，把本文件夹的 `docker-compose.yml` 内容粘贴进去。
   IP 和端口已按 `.env` 填好：`192.168.31.65:36789`，无需再改。若 NAS 地址变了，
   同步修改 api 服务里的 `ORIGIN` / `RP_ID` 和 web 服务的 `ports:`（左边是宿主机端口）。
   端口 `36789` 若被其他应用占用，改 `ports:` 左边的数字，`ORIGIN` 跟着改。

5. **启动并访问**：项目启动后浏览器打开 `http://192.168.31.65:36789/opengym/`，注册第一个账号即可。应用整体挂在 `/opengym` 前缀下（`BASE_PATH`），前后端都在这个前缀里。直接访问根路径 `/`、`/index.html` 或任何不带前缀的地址会被 nginx **308 跳转**到 `/opengym/` 下的同一路径（修正版模板已烧进 web 镜像），不会出现第二个"假"入口。

## 常见问题

- **保存被拒（"This server only takes changes made at ..."）**：`ORIGIN`/`RP_ID` 和
  实际访问地址不一致。改成报错提示里的地址，然后**重新部署项目**（重建容器，普通
  重启不生效）。
- **Passkey（通行密钥）**：浏览器要求 passkey 必须走 HTTPS + 域名，纯局域网 HTTP 用不了。
  compose 里已默认 `PASSWORD_LOGIN=1` 用账号密码登录。想要 passkey / 手机配对 / 推送，
  需再加一层 HTTPS 反向代理（如 Nginx Proxy Manager 容器 + 自己的域名），然后把
  `ORIGIN`/`RP_ID` 换成该域名，并删掉 `PASSWORD_LOGIN=1`。
- **禁止游客 / 限制注册 / 管理员**：compose 已设 `ALLOW_GUEST=0`（无游客入口）、
  `FIRST_USER_ADMIN=1`（你注册的第一个档案自动成为管理员，**没有内置默认管理员账号密码**，
  名字和密码都是你自己注册时定的）和 `INVITE_ONLY=1`（注册必须填邀请码，码在应用内
  `/admin` 面板的 **Invite codes** 卡片生成，可随时吊销）。⚠ `INVITE_ONLY` 已启用：
  **若还没注册过你自己的档案，先注释掉它、部署、注册、再取消注释重新部署**，否则连
  第一个账号都进不去（还没有管理员能发码）。
- **两个容器都要有**：只跑 web 也能打开页面，但登录全部失败。项目里能看到
  `opengym-api` 和 `opengym-web` 两个容器才对。
- **子路径（/opengym）**：由 web 和 api 的 `BASE_PATH=/opengym` 控制，前缀只在这一处变量里，
  改它即可换前缀（不要带末尾斜杠）。`ORIGIN`/`RP_ID` 始终不带路径。
- **权限**：api 容器以 root 写数据，正常 SMB/NFS 共享都没问题；若日志出现 `EACCES`，
  检查共享文件夹是否开了只读或 root 限制（见部署步骤 3 的权限说明）。
- **手机 app 配对报「它拒绝了应用的请求（CORS）」**：手机 app 的 WebView 来源是
  `https://localhost`（Android）/ `capacitor://localhost`（iOS），对服务器的每个带请求体
  或带 token 的请求都先发 OPTIONS 预检，**openGym 的 api 自己应答预检**。外层 nginx
  注意两点：不要在 server 级挂全局 CORS `add_header`（会被没有自身 add_header 的
  location 继承，叠在 api 的应答上变成两个不同的 `Access-Control-Allow-Origin`）；
  也不要用 `if ($request_method = OPTIONS) { return 204; }` 之类抢答预检。/opengym
  路由一个 CORS 头都不加、OPTIONS 原样透传即可。详见 docs/SELF_HOSTING.md
  「Phone app and CORS」。**链路上若有第二层代理（UGOS 面板反代、网关类应用）把
  `Origin` 改写成它的上游地址，回显就对不上、报同样的错** —— 判断方法：带
  `Origin: https://localhost` 发预检，看回显的 `Access-Control-Allow-Origin` 是不是
  还是 `https://localhost`；变成了别的地址就是中间那层干的，让它原样传递请求头或
  绕开它（443 由自己的 nginx 直接终结）。
- **升级**：导入新版 tar（tag 更高），改 compose 里的 `image:` 两行，重新部署项目。
  数据在 `data/` 文件夹里，不受影响。注意：web 镜像必须用**带修正模板**的本机构建版
  （见下节），直接换官方 ghcr 预构建镜像会丢掉根路径 308 跳转。
- **域名反向代理（HTTPS + /opengym）**：外层 nginx 把 `/opengym` 转到
  `http://NAS的IP:36789` 时，`proxy_pass` **不要带末尾斜杠**（前缀原样透传，容器内
  `BASE_PATH=/opengym` 自己处理）；带斜杠会剥掉前缀，容器把 `/` 打回 `/opengym/`，
  就是 **ERR_TOO_MANY_REDIRECTS**。参考块（含上传体积与超时）：

  ```nginx
  location = /opengym { return 301 /opengym/; }
  location /opengym/ {
      proxy_pass http://192.168.31.65:36789;   # 无末尾斜杠！
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      client_max_body_size 112m;
      proxy_read_timeout 300s;
  }
  ```

  **双地址（域名 + IP 都能登录存写）**：compose 的 `ORIGIN` 填 `http://<NAS的IP>:36789`
  （不是域名）。api 的存写门槛优先认浏览器自带的 `Sec-Fetch-Site: same-origin`（页面
  请求自己的地址时必然携带、网页无法伪造），`ORIGIN` 只是老浏览器的后备比对；而
  `ORIGIN` 一旦是 https，会话 cookie 带 `Secure` 标志，http 的 IP 地址就无法保持登录。
  填 http 的 IP 后，域名(https) 和 IP(http) 两个地址都能登录、存写，功能完全一致
  （两个地址的浏览器会话独立，各自登录一次即可）。局限：iOS 16.4 以前的旧 Safari 走
  域名存写会被拒。以后要启用 passkey 时，把 `ORIGIN`/`RP_ID` 换成域名（passkey 只能
  绑一个主机，届时 IP 地址只能看不能存），换可信证书（自签证书浏览器不认 passkey），
  再删掉 `PASSWORD_LOGIN=1`。

## 再次构建（本机）

一条命令（在仓库任意目录）：

```bash
./ugreen-deploy/build.sh
```

脚本保证 web 镜像一定使用 `ugreen-deploy/nginx.conf.template`（修正版），不依赖人记得
任何步骤：

1. 先校验修正版带着修正标记（被原版覆盖过会直接拒绝构建）；
2. 构建前自动用它覆盖 `web/nginx.conf.template`，构建结束**无论成败**都自动还原，
   仓库不留改动；
3. 构建后**从镜像里把模板读回来逐字节比对**，不一致直接报错、绝不导出 tar；
4. 上游模板与基线（`template-baseline.sha`）不同（升级了源码）会先停下来，要求把
   三处改动重新套用到新版模板（清单在修正版文件头），再跑
   `./ugreen-deploy/build.sh --refresh-baseline`。

版本号自动取自 `frontend/package.json`，镜像 tag 和 tar 名跟着走；版本变化后记得同步
改 `docker-compose.yml` 里的 `image:` 两行。

注意：`opengym-*.tar` 已被 .gitignore 排除，不要提交进仓库。
