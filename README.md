<a name="readme-top"></a>

<div align="center">

<img src="docs/pictures/banner.png" alt="LitePan" width="100%">

<br>

<a href="https://www.litepan.top"><img src="https://img.shields.io/badge/官网文档-www.litepan.top-6C63FF?style=for-the-badge&labelColor=1B1B2F" alt="官网文档"></a>
&nbsp;
<a href="https://space.bilibili.com/1501989416"><img src="https://img.shields.io/badge/Bilibili-交流与演示-00A1D6?style=for-the-badge&logo=bilibili&logoColor=white&labelColor=1B1B2F" alt="Bilibili"></a>
&nbsp;
<a href="https://hub.docker.com/r/ponphil/litepan"><img src="https://img.shields.io/badge/Docker-ponphil%2Flitepan-2496ED?style=for-the-badge&logo=docker&logoColor=white&labelColor=1B1B2F" alt="Docker"></a>


[![docker-pulls][docker-pulls-shield]][docker-url]
[![version][version-shield]][docker-url]
[![license][license-shield]][license-url]

</div>

<br>

> [!CAUTION]
> 当前仓库是正在开发中的 **Go 版 LitePan**，首次发布可能问题较多，请谨慎测试。
> Python 旧版已归档至 [LitePan-old](https://github.com/Ponphil/LitePan-old)。


<br>

## ▎ 功能简述

<table>
  <tr>
    <td width="50%" valign="top" align="center">
      <h3>多网盘聚合</h3>
      <p align="left">多账号统一管理，一个界面看完。</p>
      <img src="docs/pictures/feature-browser.png" alt="多网盘聚合" height="220">
    </td>
    <td width="50%" valign="top" align="center">
      <h3>跨盘秒传</h3>
      <p align="left">能秒传就秒传，否则自动上传。</p>
      <img src="docs/pictures/feature-crosstransfer.png" alt="跨盘秒传" height="220">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top" align="center">
      <h3>STRM 直连播放</h3>
      <p align="left">生成 <code>.strm</code>，对接 Emby / Jellyfin。</p>
      <img src="docs/pictures/feature-strm.png" alt="STRM 直连播放" height="220">
    </td>
    <td width="50%" valign="top" align="center">
      <h3>STRM 刮削</h3>
      <p align="left">写 nfo / 海报，海报墙可追更。</p>
      <img src="docs/pictures/feature-strm-scrape.png" alt="STRM 刮削" height="220">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top" align="center">
      <h3>目录整理</h3>
      <p align="left">TMDB 识别，预览后再归档。</p>
      <img src="docs/pictures/feature-organize.png" alt="目录整理" height="220">
    </td>
    <td width="50%" valign="top" align="center">
      <h3>自动联动</h3>
      <p align="left">整理、STRM、刮削、刷库串起来。</p>
      <img src="docs/pictures/feature-automation.png" alt="自动联动" height="220">
    </td>
  </tr>
</table>

## ▎ 挂载与更多功能

支持 WebDAV 与 FUSE 本地挂载，另有 302 直链、缓存保持、命名对齐、离线下载等能力。

---

## ▎ 快速开始

**Docker Compose 部署** · 镜像标签：`Beta`或指定`v0.5.7-Beta`

```yaml
services:
  litepan:
    image: ponphil/litepan:beta
    container_name: litepan
    restart: unless-stopped
    ports:
      - "8080:8080"
      # 内置 Magnet 的 TCP/uTP/DHT 监听端口；若在后台修改，需同步调整映射
      - "42069:42069/tcp"
      - "42069:42069/udp"
    environment:
      - TZ=Asia/Shanghai
      # 可选：外接数据库配置（默认使用内置 SQLite）
      # - LITEPAN_DB_DRIVER=mysql
      # - LITEPAN_DB_DSN=user:password@tcp(host:port)/dbname?charset=utf8mb4&parseTime=true&loc=Local
    volumes:
      - ./data:/app/data
      - ./strm:/app/strm
      - ./mounts:/app/mounts:shared

      # 可选：将 FUSE 读缓存单独映射，建议放到更快的磁盘
      # - ./fuse_read_cache:/app/data/fuse_read_cache
    devices:
      - /dev/fuse:/dev/fuse
    pid: "host"
    privileged: true
    # 没有代理环境的，可以在下方配置tmdb的hosts
    # extra_hosts:
      # - "api.themoviedb.org:这里填写对应的ip"
      # - "image.tmdb.org:这里填写对应的ip"
    # 注意：也可以在程序内「目录整理 → TMDB 设置」填写反代主域名（自动补 /3 与 /t/p），与 hosts 二选一即可
```

打开 `http://你的IP:8080`，默认管理员密码均为admin。  
需要 FUSE 时请确保宿主机具备 `/dev/fuse` 权限。

> [!WARNING]
> **不要用 `ponphil/litepan:latest` 部署本仓库对应的 Go 版。**  
> `latest` 仍是 Python 旧版镜像。若你需要旧版程序与 Compose 脚本，请前往归档仓库：[LitePan-old](https://github.com/Ponphil/LitePan-old)。




注意！！！由于您的项目是从上游（原作者）Fork 过来的，并且我们在其中**深度定制了底层数据库代码（加入了 MySQL 支持）并修改了端口**，因此在同步上游更新时，有几点非常重要的事情需要注意。

以下是同步上游更新的最常用方法和注意事项：

### 方法一：通过 GitHub 网页端一键同步（最简单）
1. 登录 GitHub，进入您自己的 `workerspages/LitePan` 仓库主页。
2. 在代码列表的上方，找到一个写着 **"Sync fork"**（同步分支）的下拉按钮。
3. 点击它，GitHub 会检查原作者的仓库是否有新的提交。
4. 如果有更新，点击 **"Update branch"** 即可自动将原作者的新代码合并到您的仓库中。
5. 合并完成后，您的 GitHub Actions 会自动触发，为您构建包含最新功能的镜像。

### ⚠️ 核心警告：可能会遇到“合并冲突 (Merge Conflict)”
因为我们修改了原项目核心的配置文件 (`internal/config/config.go`) 和数据库模块 (`internal/store/...`)，如果原作者恰好也修改了这几个文件（比如增加了新的数据库字段、修改了配置结构），点击 "Sync fork" 时，GitHub 可能会提示 **"This branch has conflicts that must be resolved"**。

**如果遇到冲突该怎么办？**
* GitHub 会提供一个 Web 编辑器让您手动解决冲突。
* 在解决冲突时，**必须保留我们新加的 MySQL 逻辑**（比如 `gorm` 相关的代码），同时合并原作者的新功能。
* **建议：** 如果您遇到了解决不了的冲突，可以随时将冲突的代码发给我，或者让我帮您拉取代码进行合并，我会帮您保留 MySQL 兼容性的同时接入最新功能。

### 方法二：通过本地命令行同步（进阶版）
如果您习惯使用本地 Git 环境，可以通过以下命令拉取并合并上游更新：

```bash
# 1. 添加原作者的仓库地址为 upstream (仅需执行一次)
git remote add upstream https://github.com/原作者的用户名/LitePan.git

# 2. 拉取原作者的最新代码
git fetch upstream

# 3. 切换到您的 main 分支
git checkout main

# 4. 将原作者的代码合并到您的分支
git merge upstream/main

# 5. 如果有冲突，手动修改文件解决冲突后提交
git add .
git commit -m "Merge upstream updates"

# 6. 推送到您自己的 GitHub
git push origin main
```

**总结：**
日常您可以偶尔点一下 GitHub 页面上的 **"Sync fork"**。如果一切顺利自动合并了，那就万事大吉；如果报错提示冲突，先不要慌，不要直接覆盖掉我们的修改，您可以随时带着冲突回来找我！














## ▎ 支持

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>支持 LitePan</h3>
      <p>如果这个项目对你有帮助，欢迎点右上角 <strong>Star</strong>，也欢迎自愿赞赏。</p>
      <img src="docs/pictures/wechat-tip.png" alt="微信赞赏" width="260">
    </td>
    <td width="50%" valign="top">
      <h3>赞助致谢</h3>
      <p>感谢每一位支持 LitePan 的朋友。</p>
      <p>完整致谢名单见官方网站：</p>
      <p>
        <a href="https://www.litepan.top/sponsor.html">https://www.litepan.top/sponsor.html</a>
      </p>
    </td>
  </tr>
</table>

## ▎ 反馈

交流请到 <a href="https://space.bilibili.com/1501989416">B 站主页</a>。  
暂不接受公开 PR；有维护意愿请私信。
外部贡献致谢见 [ACKNOWLEDGEMENTS.md](./ACKNOWLEDGEMENTS.md)。

---

## ▎ 许可

[PolyForm Noncommercial 1.0.0](./LICENSE) — 个人学习与非商业使用，**禁止商用**。  
第三方依赖见 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。请遵守各网盘服务条款与当地法规。

[docker-pulls-shield]: https://img.shields.io/docker/pulls/ponphil/litepan?logo=docker&logoColor=white&style=flat-square
[version-shield]: https://img.shields.io/badge/Version-v0.5.7--Beta-6C63FF?style=flat-square
[license-shield]: https://img.shields.io/badge/License-PolyForm%20NC-red?style=flat-square
[docker-url]: https://hub.docker.com/r/ponphil/litepan
[license-url]: ./LICENSE
