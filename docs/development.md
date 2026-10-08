# 开发与测试

## 源码运行

Windows 自带 PowerShell 5.1 即可运行，无需 Python / Node.js。双击根目录 `启动SZU电查查.bat`，或执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server.ps1 -Port 18765 -OpenBrowser
```

前端是浏览器原生 JavaScript、CSS 和 SVG，没有打包步骤和运行时网络依赖。`package.json` 只用于开发测试。

## 核心测试

```powershell
node --test tests/model.test.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File tests/query.test.ps1
```

这些测试使用合成数据，覆盖分页完整性、重复页、HTML 解析、跨日统计、读数回退、购电时间归属、费用估算和 CSV 转义。GitHub Actions 自动运行它们并构建 Windows 版；不会访问校园网，也不会查询真实宿舍。

## 浏览器验证

安装开发依赖：

```powershell
npm ci
npx playwright install chromium
```

启动两个服务，使用同一个独立测试配置目录，避免覆盖自己的宿舍设置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server.ps1 -Port 18767 -DataDir "$PWD\tests\.runtime"
powershell -NoProfile -ExecutionPolicy Bypass -File server.ps1 -Port 18768 -DataDir "$PWD\tests\.runtime"
```

另开终端执行：

```powershell
$env:TEST_URL='http://127.0.0.1:18767'
$env:SECOND_TEST_URL='http://127.0.0.1:18768'
npm run test:ui
npm run test:startup
```

浏览器测试将真实查询响应替换为模拟数据，验证自动启动、两个图表、侧边栏定位、充值卡片、筛选、导出和手机布局。宿舍偏好验证使用独立测试目录，并检查新浏览器与另一服务端口恢复设置。可用 `BROWSER_CHANNEL=msedge` 使用本机 Edge；`PLAYWRIGHT_PATH` 可指定现有 Playwright 包路径。

运行 `node tests/capture-demo.cjs` 可重新生成 `docs/images/` 下的公开演示截图，同时验证首次打开没有预设房间、不会自动请求校园数据。截图只使用前端模拟数据。

## 构建免安装 exe

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File packaging/build.ps1
```

编译器使用 Windows 自带 .NET Framework C# 编译器。输出为 `dist/SZU电查查.exe` 和源码版压缩包；生成的源码与资源归档放在 `.build/`。这些目录均不提交到 Git。运行中的 exe 可能锁定输出文件，重建前请关闭同版本查询服务。

可选的真实查询验证需要 Python 和校园网：

```powershell
$env:SZU_TEST_CAMPUS='你的校区'
$env:SZU_TEST_BUILDING='你的楼栋'
$env:SZU_TEST_ROOM='你的房间号'
python tests/portable.test.py
```

该测试把 exe 复制到只有一个文件的临时目录，核对资源、重复启动、真实查询和关闭服务；不固定房间、日期或记录数量，也不保存真实查询明细。未设置测试宿舍时只验证启动和资源，不查询校园系统。

