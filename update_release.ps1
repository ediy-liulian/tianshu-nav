# ============================================================
# 天枢导航 GitHub 仓库 · 一键更新脚本（修正版 2026-10-31）
# 用法：双击 update_release.bat（或右键用 PowerShell 运行本文件）
# 功能：自动检测最新版本 → 拷贝产物 → 清理历史 → 更新 README → 提交并推送
# 前提：新产物已由打包脚本生成到 03-产物归档（按「第N轮交付包_vX」嵌套目录）
#
# 相对原版修正点：
#   1. 源路径改到项目迁移后的 E:\ 位置
#   2. 版本检测改为扫描 03-产物归档 下最新的「第N轮交付包_vX」嵌套目录
#   3. 清单解析正则适配新格式  | 包 | 文件 | `HASH` | 大小 B |
#   4. README 末尾清单链接随版本更新
#   5. 版本号替换正则兼容 1.1.x 与 1.00.x（先读出旧版本号再全量替换）
#   6. 版本排序统一用 [version] 比较，避免 PowerShell 对数组排序键的不稳定行为
# ============================================================
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$projRoot = 'E:\1-Agent-works\A-my_project\天枢导航'
$src  = Join-Path $projRoot '03-产物归档'

Write-Host ''
Write-Host '========== 天枢导航 GitHub 仓库一键更新（修正版） ==========' -ForegroundColor Cyan

# ---------- 1. 检测最新版本（扫描最新的 第N轮交付包_vX 目录） ----------
$roundDirs = Get-ChildItem -LiteralPath $src -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^第\d+轮交付包_v([0-9.]+)$' }
if (-not $roundDirs) {
    Write-Host "未找到版本目录：03-产物归档 下没有 第N轮交付包_vX 目录" -ForegroundColor Red
    Write-Host '请先用打包脚本生成产物后再运行本脚本。' -ForegroundColor Red
    exit 1
}
$roundDir = $roundDirs | ForEach-Object {
    $v = [regex]::Match($_.Name, '^第\d+轮交付包_v([0-9.]+)$').Groups[1].Value
    [PSCustomObject]@{ Dir = $_; Ver = $v }
} | Sort-Object { [version]$_.Ver } -Descending | Select-Object -First 1
$ver = $roundDir.Ver
$roundPath = $roundDir.Dir.FullName
Write-Host ('检测到最新版本：{0}（目录 {1}）' -f $ver, $roundDir.Dir.Name) -ForegroundColor Green

# ---------- 1.1 校验必备产物 ----------
$need = @(
    "FPK安装包\tianshu-nav-$ver-x86.fpk",
    "FPK安装包\tianshu-nav-$ver-arm.fpk",
    "客户端-完整包\tianshu-nav-v$ver.zip",
    "Docker离线部署包\tianshu-nav-docker-$ver-x86.zip",
    "Docker离线部署包\tianshu-nav-docker-$ver-arm.zip",
    "SHA256清单-正式版递增-v$ver.md"
)
$missing = $need | Where-Object { -not (Test-Path -LiteralPath (Join-Path $roundPath $_)) }
if ($missing) {
    Write-Host ('缺少产物，终止：' + ($missing -join ', ')) -ForegroundColor Red
    exit 1
}

# ---------- 2. 拷贝产物 ----------
$copies = @(
    @{ src = "FPK安装包\tianshu-nav-$ver-x86.fpk";              dst = "fpk\tianshu-nav-$ver-x86.fpk" },
    @{ src = "FPK安装包\tianshu-nav-$ver-arm.fpk";              dst = "fpk\tianshu-nav-$ver-arm.fpk" },
    @{ src = "客户端-完整包\tianshu-nav-v$ver.zip";              dst = "docker\tianshu-nav-v$ver.zip" },
    @{ src = "Docker离线部署包\tianshu-nav-docker-$ver-x86.zip"; dst = "docker\tianshu-nav-docker-$ver-x86.zip" },
    @{ src = "Docker离线部署包\tianshu-nav-docker-$ver-arm.zip"; dst = "docker\tianshu-nav-docker-$ver-arm.zip" },
    @{ src = "SHA256清单-正式版递增-v$ver.md";                    dst = "SHA256清单-正式版递增-v$ver.md" }
)
foreach ($c in $copies) {
    $s = Join-Path $roundPath $c.src
    $d = Join-Path $repo $c.dst
    New-Item -ItemType Directory -Force (Split-Path $d -Parent) | Out-Null
    Copy-Item -LiteralPath $s -Destination $d -Force
    Write-Host ('已拷贝：{0}' -f $c.dst) -ForegroundColor DarkGray
}

# ---------- 3. 清理历史（保留 最新 + 上一版 + 正式首版 1.00.001） ----------
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
$prev = if ($vers.Count -ge 2) {
    ($vers | Sort-Object { [version]$_ } -Descending)[1]
} else { '' }
$keep = @($ver, $prev, '1.00.001') | Where-Object { $_ }
Write-Host ('保留版本：{0}' -f ($keep -join ', ')) -ForegroundColor DarkGray
foreach ($dir in @('fpk', 'docker')) {
    Get-ChildItem -LiteralPath (Join-Path $repo $dir) -File -ErrorAction SilentlyContinue | ForEach-Object {
        $m = [regex]::Match($_.Name, '([0-9]+\.[0-9]+\.[0-9]+)')
        if ($m.Success -and $m.Groups[1].Value -notin $keep) {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Host ('清理旧版本：{0}' -f $_.Name) -ForegroundColor DarkGray
        }
    }
}
# 清理旧版 SHA256 清单（保留当前 + 上一版）
Get-ChildItem -LiteralPath $repo -Filter 'SHA256清单-正式版递增-v*.md' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $m = [regex]::Match($_.Name, 'v([0-9.]+)\.md$')
    if ($m.Success -and $m.Groups[1].Value -notin $keep) {
        Remove-Item -LiteralPath $_.FullName -Force
        Write-Host ('清理旧清单：{0}' -f $_.Name) -ForegroundColor DarkGray
    }
}

# ---------- 4. 更新 README ----------
$readme = Join-Path $repo 'README.md'
$content = Get-Content -LiteralPath $readme -Raw -Encoding UTF8

# 4.0 读出旧版本号（从「当前版本：X」），全量替换（兼容 1.1.x 与 1.00.x）
$oldVer = [regex]::Match($content, '当前版本：(\d+\.\d+\.\d+)').Groups[1].Value
if ($oldVer) {
    $content = $content -replace [regex]::Escape($oldVer), $ver
    Write-Host ('README 版本号 {0} -> {1}' -f $oldVer, $ver) -ForegroundColor DarkGray
} else {
    Write-Host '警告：未在 README 中找到「当前版本：X」，版本号可能未替换' -ForegroundColor Yellow
}

# 4.2 版本说明行日期更新为当天
$today = Get-Date -Format 'yyyy-MM-dd'
$content = [regex]::Replace($content, '（客户端 / 服务器端同号，\d{4}-\d{2}-\d{2}）', "（客户端 / 服务器端同号，$today）")

# 4.3 重建下载表（从新 SHA256 清单解析 文件名 / 大小 / 哈希，适配新格式）
$manifest = Join-Path $repo "SHA256清单-正式版递增-v$ver.md"
if (Test-Path -LiteralPath $manifest) {
    $rows = @()
    Get-Content -LiteralPath $manifest -Encoding UTF8 | ForEach-Object {
        # 新格式：| 包 | 文件名 | `HASH` | 大小 B |
        $m = [regex]::Match($_, '^\|[^|]*\|\s*([A-Za-z0-9_.\-]+\.(?:fpk|zip))\s*\|\s*`?([0-9A-Fa-f]{64})`?\s*\|\s*([\d,]+)\s*B\s*\|')
        if (-not $m.Success) { return }
        $file   = $m.Groups[1].Value
        $sha    = $m.Groups[2].Value.ToUpper()
        $sizeB  = [double]($m.Groups[3].Value -replace ',', '')
        $sizeMB = [math]::Round($sizeB / 1MB, 1)
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
    if ($rows.Count -eq 0) {
        Write-Host '警告：清单解析为 0 行，README 下载表未更新（请手动核对）' -ForegroundColor Yellow
    } else {
        $tbl = '| 文件 | 架构 | 说明 | 大小 | SHA256 |' + "`n" + '| --- | --- | --- | --- | --- |' + "`n"
        foreach ($r in $rows) {
            $tbl += ('| {0} | {1} | {2} | {3:0.0} MB | {4} |' -f ("``" + $r.path + "``"), $r.arch, $r.desc, $r.size, ("``" + $r.sha + "``")) + "`n"
        }
        $tbl = $tbl.TrimEnd("`n")
        $content = [regex]::Replace($content, '\| 文件 \| 架构 \| 说明 \| 大小 \| SHA256 \|[\s\S]*?完整 SHA256 清单见', ($tbl + "`n`n完整 SHA256 清单见"), 1)
        # 4.4 同步清单链接文件名（README 末尾 [SHA256清单-正式版递增-vX.md]）
        $content = [regex]::Replace($content, 'SHA256清单-正式版递增-\d+\.\d+\.\d+\.md', "SHA256清单-正式版递增-v$ver.md")
        Write-Host 'README 下载表已按新 SHA256 清单重建' -ForegroundColor DarkGray
    }
} else {
    Write-Host '警告：未找到新 SHA256 清单，README 下载表未更新（请手动核对）' -ForegroundColor Yellow
}

# 4.5 写回（UTF-8 无 BOM）
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($readme, $content, $utf8NoBom)
Write-Host 'README 已更新（版本号 / 日期 / 下载表 / 清单链接）' -ForegroundColor Green

# ---------- 5. 提交并推送 ----------
Write-Host '提交并推送中……' -ForegroundColor Cyan
git -C $repo add -A
git -C $repo commit -m "更新：天枢导航 $ver 客户端安装包"
git -C $repo push

Write-Host ''
Write-Host ('========== 完成：仓库已更新到 {0} ==========' -f $ver) -ForegroundColor Green
