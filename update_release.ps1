# ============================================================
# 天枢导航 GitHub 仓库 · 一键更新脚本（修正版 2026-10-31 v2 · 铁律合规）
# 用法：双击 update_release.bat（或右键用 PowerShell 运行本文件）
# 功能：自动检测最新版本 → 拷贝产物 → 清理历史 → 更新 README → 提交并推送
# 前提：新产物已由打包脚本生成到 03-产物归档（按「第N轮交付包_vX」嵌套目录）
#
# ★ 铁律（项目规定，强制）★
#   1. GitHub 只发布【客户端飞牛 FPK】+【Docker 部署包】，且必须为【混淆版（OBF）】。
#      Docker 部署包分两种，均合规：
#        - 离线部署包（含预构建镜像 tar，约 60MB）
#        - 在线部署包（不含镜像，仅含混淆后的 server/ + public/ + Dockerfile，本地构建镜像，约 2MB）
#      绝不发布：客户端完整包 / 客户端升级包 / 未混淆源码包 / 服务器端包。
#      “在线部署包”仅限混淆版（本地从混淆代码构建，不含可读源码，防泄露与盗版）。
#   2. 历史版本【只保留最新 1 个】：每次发新版即删除所有旧版本，仓库不留存任何历史版本（2026-11-06 用户拍板，推翻旧“保留近3版”）。
#
# 相对 v1 修正点：
#   1. 源路径改到 E:\（项目迁移后位置）
#   2. 版本检测扫描最新的「第N轮交付包_vX」嵌套目录
#   3. 清单解析正则适配新格式  | 包 | 文件 | `HASH` | 大小 B |
#   4. README 末尾清单链接随版本更新
#   5. 版本号替换兼容 1.1.x 与 1.00.x（先读旧版本号再全量替换）
#   6. 版本排序统一用 [version] 比较
#   7. 【铁律】只拷贝 FPK(x86/arm) + Docker 离线(x86/arm)，删除“在线部署包/客户端完整包”映射
#   8. 【铁律】SHA256 清单只保留实际发布的 4 个文件
#   9. 【铁律】历史版本只保留最新 1 个（每次发新版删除所有旧版，不留历史；2026-11-06 起生效）
#  10. 默认密码随产品变化，README“初始密码”需人工核对（脚本不自动改写）
# ============================================================
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$projRoot = 'E:\1-Agent-works\A-my_project\天枢导航'
$src  = Join-Path $projRoot '03-产物归档'

# 解析 Python（优先用 WorkBuddy 捆绑的真实 python，避免 WindowsApps 桩）
$py = (Get-ChildItem 'C:\Users\Administrator\.workbuddy\binaries\python\versions\*\python.exe' -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
if (-not $py) { $py = 'python3' }

Write-Host ''
Write-Host '========== 天枢导航 GitHub 仓库一键更新（FPK + Docker 离线/在线，仅混淆版，只保留最新版） ==========' -ForegroundColor Cyan

# ---------- 1. 检测最新版本 ----------
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

# ---------- 1.1 校验必备产物（仅 FPK x86/arm + Docker 离线 x86/arm + 清单） ----------
$need = @(
    "FPK安装包\tianshu-nav-$ver-x86.fpk",
    "FPK安装包\tianshu-nav-$ver-arm.fpk",
    "Docker离线部署包\tianshu-nav-docker-$ver-x86.zip",
    "Docker离线部署包\tianshu-nav-docker-$ver-arm.zip",
    "SHA256清单-正式版递增-v$ver.md"
)
$missing = $need | Where-Object { -not (Test-Path -LiteralPath (Join-Path $roundPath $_)) }
if ($missing) {
    Write-Host ('缺少产物，终止：' + ($missing -join ', ')) -ForegroundColor Red
    exit 1
}

# ---------- 2. 拷贝产物（仅 FPK + Docker 离线，混淆版） ----------
$copies = @(
    @{ src = "FPK安装包\tianshu-nav-$ver-x86.fpk";              dst = "fpk\tianshu-nav-$ver-x86.fpk" },
    @{ src = "FPK安装包\tianshu-nav-$ver-arm.fpk";              dst = "fpk\tianshu-nav-$ver-arm.fpk" },
    @{ src = "Docker离线部署包\tianshu-nav-docker-$ver-x86.zip"; dst = "docker\tianshu-nav-docker-$ver-x86.zip" },
    @{ src = "Docker离线部署包\tianshu-nav-docker-$ver-arm.zip"; dst = "docker\tianshu-nav-docker-$ver-arm.zip" }
)
foreach ($c in $copies) {
    $s = Join-Path $roundPath $c.src
    $d = Join-Path $repo $c.dst
    New-Item -ItemType Directory -Force (Split-Path $d -Parent) | Out-Null
    Copy-Item -LiteralPath $s -Destination $d -Force
    Write-Host ('已拷贝：{0}' -f $c.dst) -ForegroundColor DarkGray
}
# 拷贝 SHA256 清单（随后过滤为仅发布文件）
$manifestSrc = Join-Path $roundPath "SHA256清单-正式版递增-v$ver.md"
$manifestDst = Join-Path $repo "SHA256清单-正式版递增-v$ver.md"
Copy-Item -LiteralPath $manifestSrc -Destination $manifestDst -Force

# ---------- 2.5 构建 Docker 在线部署包（混淆版，本地构建镜像，约 2MB） ----------
# 从「Docker 离线部署包」的已验证镜像层中抽取 server/(含 node_modules) + public/（均为混淆版），
# 加 Dockerfile / docker-compose.yml(build:) / 脚本，打包为 docker/tianshu-nav-docker-online-V-{x86,arm}.zip
Write-Host '构建 Docker 在线部署包（混淆版）……' -ForegroundColor Cyan
& $py (Join-Path $repo 'build_online_pkg.py') $projRoot $ver (Get-Date -Format 'yyyy-MM-dd')
if ($LASTEXITCODE -ne 0) {
    Write-Host '在线包构建失败（Python 步骤异常），终止' -ForegroundColor Red
    exit 1
}
Write-Host 'Docker 在线部署包已构建（x86 / arm）' -ForegroundColor DarkGray

# ---------- 2.6 把在线包哈希追加进 SHA256 清单（置于表格数据区、注释之前） ----------
function Get-Sha256($f) {
    $algo = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.IO.File]::ReadAllBytes($f)
    return (($algo.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
}
$mfLines = Get-Content -LiteralPath $manifestDst -Encoding UTF8
$newRows = @()
foreach ($oname in @("tianshu-nav-docker-online-$ver-x86.zip", "tianshu-nav-docker-online-$ver-arm.zip")) {
    $of = Join-Path $repo ("docker\" + $oname)
    if (-not (Test-Path -LiteralPath $of)) { continue }
    $size = (Get-Item -LiteralPath $of).Length
    $hash = Get-Sha256 $of
    $newRows += ("| Docker部署包 | {0} | `{1}` | {2} B |" -f $oname, $hash, $size)
    Write-Host ('已登记在线包哈希：{0}' -f $oname) -ForegroundColor DarkGray
}
$lastTableIdx = -1
for ($i = 0; $i -lt $mfLines.Count; $i++) { if ($mfLines[$i] -match '^\|') { $lastTableIdx = $i } }
if ($lastTableIdx -ge 0 -and $newRows.Count -gt 0) {
    $mfLines = $mfLines[0..$lastTableIdx] + $newRows + $mfLines[($lastTableIdx + 1)..($mfLines.Count - 1)]
    [IO.File]::WriteAllText($manifestDst, ($mfLines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ('SHA256 清单已追加 {0} 个在线包条目' -f $newRows.Count) -ForegroundColor DarkGray
}

# ---------- 3. 清理历史（只保留最新 1 个版本，删掉所有旧版） ----------
$vers = @()
Get-ChildItem -LiteralPath (Join-Path $repo 'fpk') -Filter 'tianshu-nav-*-*.fpk' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $m = [regex]::Match($_.Name, 'tianshu-nav-([0-9.]+)-')
    if ($m.Success) { $vers += $m.Groups[1].Value }
}
Get-ChildItem -LiteralPath (Join-Path $repo 'docker') -Filter '*.zip' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $m = [regex]::Match($_.Name, '([0-9]+\.[0-9]+\.[0-9]+)')
    if ($m.Success) { $vers += $m.Groups[1].Value }
}
$vers = $vers | Sort-Object -Unique { [version]$_ } -Descending
$keep = $vers | Select-Object -First 1
Write-Host ('保留版本（仅最新 1 个）：{0}' -f ($keep -join ', ')) -ForegroundColor DarkGray
foreach ($dir in @('fpk', 'docker')) {
    Get-ChildItem -LiteralPath (Join-Path $repo $dir) -File -ErrorAction SilentlyContinue | ForEach-Object {
        $m = [regex]::Match($_.Name, '([0-9]+\.[0-9]+\.[0-9]+)')
        if ($m.Success -and $m.Groups[1].Value -notin $keep) {
            git -C $repo rm -f --ignore-unmatch -- $_.FullName
            Write-Host ('清理旧版本：{0}' -f $_.Name) -ForegroundColor DarkGray
        }
    }
}
# 额外保险：删除任何“在线部署包”残留（docker/tianshu-nav-v*.zip 模式，铁律不允许发布）
Get-ChildItem -LiteralPath (Join-Path $repo 'docker') -Filter 'tianshu-nav-v*.zip' -File -ErrorAction SilentlyContinue | ForEach-Object {
    git -C $repo rm -f --ignore-unmatch -- $_.FullName
    Write-Host ('清理违规在线包残留：{0}' -f $_.Name) -ForegroundColor DarkGray
}
# 清理旧版 SHA256 清单（只保留最新版对应清单）
Get-ChildItem -LiteralPath $repo -Filter 'SHA256清单-正式版递增-v*.md' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $m = [regex]::Match($_.Name, 'v([0-9.]+)\.md$')
    if ($m.Success -and $m.Groups[1].Value -notin $keep) {
        git -C $repo rm -f --ignore-unmatch -- $_.FullName
        Write-Host ('清理旧清单：{0}' -f $_.Name) -ForegroundColor DarkGray
    }
}

# ---------- 3.5 过滤 SHA256 清单：只保留实际发布的 4 个文件 ----------
$published = @(
    "tianshu-nav-$ver-x86.fpk",
    "tianshu-nav-$ver-arm.fpk",
    "tianshu-nav-docker-$ver-x86.zip",
    "tianshu-nav-docker-$ver-arm.zip",
    "tianshu-nav-docker-online-$ver-x86.zip",
    "tianshu-nav-docker-online-$ver-arm.zip"
)
$rowRe = '^\|[^|]*\|\s*([A-Za-z0-9_.\-]+\.(?:fpk|zip))\s*\|'
$mLines = Get-Content -LiteralPath $manifestDst -Encoding UTF8 | ForEach-Object {
    $line = $_
    $m = [regex]::Match($line, $rowRe)
    if ($m.Success) {
        if ($published -contains $m.Groups[1].Value) { $line }
    } else {
        $line
    }
}
[IO.File]::WriteAllText($manifestDst, ($mLines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('SHA256 清单已过滤为实际发布的 {0} 个文件' -f $published.Count) -ForegroundColor DarkGray

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

# 4.3 重建下载表（仅 FPK + Docker 离线，适配新清单格式）
$manifest = Join-Path $repo "SHA256清单-正式版递增-v$ver.md"
if (Test-Path -LiteralPath $manifest) {
    $rows = @()
    Get-Content -LiteralPath $manifest -Encoding UTF8 | ForEach-Object {
        $m = [regex]::Match($_, '^\|[^|]*\|\s*([A-Za-z0-9_.\-]+\.(?:fpk|zip))\s*\|\s*`?([0-9A-Fa-f]{64})`?\s*\|\s*([\d,]+)\s*B\s*\|')
        if (-not $m.Success) { return }
        $file   = $m.Groups[1].Value
        $sha    = $m.Groups[2].Value.ToUpper()
        $sizeB  = [double]($m.Groups[3].Value -replace ',', '')
        $sizeMB = [math]::Round($sizeB / 1MB, 1)
        if ($file -match '^tianshu-nav-.*\.fpk$') {
            $arch = if ($file -match '-x86\.fpk$') { 'x86 / amd64' } else { 'ARM64' }
            $rows += @{ path = "fpk/$file"; arch = $arch; desc = '飞牛 fnOS 安装包（混淆版）'; size = $sizeMB; sha = $sha }
        } elseif ($file -match '^tianshu-nav-docker-online-.*\.zip$') {
            $arch = if ($file -match '-x86\.zip$') { 'x86 / amd64' } else { 'ARM64' }
            $rows += @{ path = "docker/$file"; arch = $arch; desc = 'Docker 在线部署包（混淆版，本地构建镜像）'; size = $sizeMB; sha = $sha }
        } elseif ($file -match '^tianshu-nav-docker-.*\.zip$') {
            $arch = if ($file -match '-x86\.zip$') { 'x86 / amd64' } else { 'ARM64' }
            $rows += @{ path = "docker/$file"; arch = $arch; desc = 'Docker 离线部署包（含镜像，混淆版）'; size = $sizeMB; sha = $sha }
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
        # 4.4 同步清单链接文件名
        $content = [regex]::Replace($content, 'SHA256清单-正式版递增-\d+\.\d+\.\d+\.md', "SHA256清单-正式版递增-v$ver.md")
        Write-Host 'README 下载表已按新 SHA256 清单重建（仅 FPK + Docker 离线）' -ForegroundColor DarkGray
    }
} else {
    Write-Host '警告：未找到新 SHA256 清单，README 下载表未更新（请手动核对）' -ForegroundColor Yellow
}

# 4.6 写回（UTF-8 无 BOM）
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($readme, $content, $utf8NoBom)
Write-Host 'README 已更新（版本号 / 日期 / 下载表 / 清单链接）' -ForegroundColor Green

# ---------- 5. 提交并推送 ----------
Write-Host '提交并推送中……' -ForegroundColor Cyan
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'   # git 的 CRLF 提示走 stderr，不应中断脚本
git -C $repo add -A
git -C $repo commit -m "更新：天枢导航 $ver（FPK + Docker 离线/在线，混淆版，仅保留最新版）"
git -C $repo push
$ErrorActionPreference = $prevEAP

Write-Host ''
Write-Host ('========== 完成：仓库已更新到 {0} ==========' -f $ver) -ForegroundColor Green
