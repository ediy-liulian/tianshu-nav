# ============================================================
# 天枢导航 GitHub 仓库 · 一键更新脚本
# 用法：双击 update_release.bat（或右键用 PowerShell 运行本文件）
# 功能：自动检测最新版本 → 拷贝产物 → 清理历史 → 更新 README → 提交并推送
# 前提：新产物已由打包脚本生成到 D:\doubao_works\chats\天枢导航\03-产物归档
# ============================================================
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$src  = 'D:\doubao_works\chats\天枢导航\03-产物归档'

Write-Host ''
Write-Host '========== 天枢导航 GitHub 仓库一键更新 ==========' -ForegroundColor Cyan

# ---------- 1. 检测最新版本（以 FPK x86 为准） ----------
$fpkX86 = Get-ChildItem -LiteralPath (Join-Path $src 'FPK安装包') -Filter 'tianshu-nav-*-x86.fpk' -File -ErrorAction SilentlyContinue |
          Sort-Object Name -Descending | Select-Object -First 1
if (-not $fpkX86) {
    Write-Host '未找到新版本产物：03-产物归档\FPK安装包 下没有 tianshu-nav-*-x86.fpk' -ForegroundColor Red
    Write-Host '请先用打包脚本生成产物后再运行本脚本。' -ForegroundColor Red
    exit 1
}
$ver = [regex]::Match($fpkX86.Name, '^tianshu-nav-([0-9.]+)-x86\.fpk$').Groups[1].Value
Write-Host ('检测到最新版本：{0}' -f $ver) -ForegroundColor Green

# ---------- 2. 拷贝产物（源存在才拷，兼容已手工放入仓库目录的情况） ----------
$copies = @(
    @{ src = "FPK安装包\tianshu-nav-$ver-x86.fpk";              dst = "fpk\tianshu-nav-$ver-x86.fpk" },
    @{ src = "FPK安装包\tianshu-nav-$ver-arm.fpk";              dst = "fpk\tianshu-nav-$ver-arm.fpk" },
    @{ src = "客户端-完整包\tianshu-nav-v$ver.zip";              dst = "docker\tianshu-nav-v$ver.zip" },
    @{ src = "Docker离线部署包\tianshu-nav-docker-$ver-x86.zip"; dst = "docker\tianshu-nav-docker-$ver-x86.zip" },
    @{ src = "Docker离线部署包\tianshu-nav-docker-$ver-arm.zip"; dst = "docker\tianshu-nav-docker-$ver-arm.zip" },
    @{ src = "SHA256清单-正式版递增-v$ver.md";                    dst = "SHA256清单-正式版递增-v$ver.md" }
)
foreach ($c in $copies) {
    $s = Join-Path $src $c.src
    $d = Join-Path $repo $c.dst
    if (Test-Path -LiteralPath $s) {
        New-Item -ItemType Directory -Force (Split-Path $d -Parent) | Out-Null
        Copy-Item -LiteralPath $s -Destination $d -Force
        Write-Host ('已拷贝：{0}' -f $c.dst) -ForegroundColor DarkGray
    } else {
        Write-Host ('跳过（源不存在）：{0}' -f $c.src) -ForegroundColor Yellow
    }
}

# ---------- 3. 清理历史（仅保留 最新 + 上一版 + 正式首版 1.00.001） ----------
$vers = @()
Get-ChildItem -LiteralPath (Join-Path $repo 'fpk') -Filter 'tianshu-nav-*-*.fpk' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $m = [regex]::Match($_.Name, 'tianshu-nav-([0-9.]+)-')
    if ($m.Success) { $vers += $m.Groups[1].Value }
}
Get-ChildItem -LiteralPath (Join-Path $repo 'docker') -Filter '*.zip' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $m = [regex]::Match($_.Name, '([0-9]+\.[0-9]+\.[0-9]+)')
    if ($m.Success) { $vers += $m.Groups[1].Value }
}
$vers = $vers | Sort-Object -Unique
$prev = if ($vers.Count -ge 2) { $vers[-2] } else { '' }
$keep = @($ver, $prev, '1.00.001') | Where-Object { $_ }
foreach ($dir in @('fpk', 'docker')) {
    Get-ChildItem -LiteralPath (Join-Path $repo $dir) -File -ErrorAction SilentlyContinue | ForEach-Object {
        $m = [regex]::Match($_.Name, '([0-9]+\.[0-9]+\.[0-9]+)')
        if ($m.Success -and $m.Groups[1].Value -notin $keep) {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Host ('清理旧版本：{0}' -f $_.Name) -ForegroundColor DarkGray
        }
    }
}

# ---------- 4. 更新 README ----------
$readme = Join-Path $repo 'README.md'
$content = Get-Content -LiteralPath $readme -Raw -Encoding UTF8

# 4.1 版本号全量替换（当前版本行 / 文件名 / 清单引用 / 版本说明表）
$content = [regex]::Replace($content, '1\.00\.00\d+', $ver)

# 4.2 版本说明行日期更新为当天
$today = Get-Date -Format 'yyyy-MM-dd'
$content = [regex]::Replace($content, '（客户端 / 服务器端同号，\d{4}-\d{2}-\d{2}）', "（客户端 / 服务器端同号，$today）")

# 4.3 重建下载表（从新 SHA256 清单解析文件名 / 大小 / 哈希）
$manifest = Join-Path $repo "SHA256清单-正式版递增-v$ver.md"
if (Test-Path -LiteralPath $manifest) {
    $rows = @()
    Get-Content -LiteralPath $manifest -Encoding UTF8 | ForEach-Object {
        $m = [regex]::Match($_, '^([^|]+)\|\s*([A-Za-z0-9_.\-]+\.(?:fpk|zip))\s*\|\s*sha256=([0-9A-F]{64})\s*\|\s*(\d+)\s*bytes')
        if (-not $m.Success) { return }
        $file   = $m.Groups[2].Value
        $sha    = $m.Groups[3].Value
        $sizeMB = [math]::Round([double]$m.Groups[4].Value / 1MB, 1)
        if ($file -match '^tianshu-nav-.*\.fpk$') {
            $arch = if ($file -match '-x86\.fpk$') { 'x86 / amd64' } else { 'ARM64' }
            $rows += @{ path = "fpk/$file"; arch = $arch; desc = '飞牛 fnOS 安装包'; size = $sizeMB; sha = $sha }
        } elseif ($file -match '^tianshu-nav-v[0-9].*\.zip$') {
            $rows += @{ path = "docker/$file"; arch = 'x86 / ARM 通用'; desc = 'Docker 在线部署包（不含镜像，联网拉取）'; size = $sizeMB; sha = $sha }
        } elseif ($file -match '^tianshu-nav-docker-.*\.zip$') {
            $arch = if ($file -match '-x86\.zip$') { 'x86 / amd64' } else { 'ARM64' }
            $rows += @{ path = "docker/$file"; arch = $arch; desc = 'Docker 离线部署包（含镜像）'; size = $sizeMB; sha = $sha }
        }
    }
    $tbl = '| 文件 | 架构 | 说明 | 大小 | SHA256 |' + "`n" + '| --- | --- | --- | --- | --- |' + "`n"
    foreach ($r in $rows) {
        $tbl += ('| {0} | {1} | {2} | {3:0.0} MB | {4} |' -f ("``" + $r.path + "``"), $r.arch, $r.desc, $r.size, ("``" + $r.sha + "``")) + "`n"
    }
    $tbl = $tbl.TrimEnd("`n")
    $content = [regex]::Replace($content, '\| 文件 \| 架构 \| 说明 \| 大小 \| SHA256 \|[\s\S]*?完整 SHA256 清单见', ($tbl + "`n`n完整 SHA256 清单见"), 1)
    Write-Host 'README 下载表已按新 SHA256 清单重建' -ForegroundColor DarkGray
} else {
    Write-Host '警告：未找到新 SHA256 清单，README 下载表未更新（请手动核对）' -ForegroundColor Yellow
}

# 4.4 写回（UTF-8 无 BOM）
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($readme, $content, $utf8NoBom)
Write-Host 'README 已更新（版本号 / 日期 / 下载表）' -ForegroundColor Green

# ---------- 5. 提交并推送 ----------
Write-Host '提交并推送中……' -ForegroundColor Cyan
git -C $repo add -A
git -C $repo commit -m "更新：天枢导航 $ver 客户端安装包"
git -C $repo push

Write-Host ''
Write-Host ('========== 完成：仓库已更新到 {0} ==========' -f $ver) -ForegroundColor Green
