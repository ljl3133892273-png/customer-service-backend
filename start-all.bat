@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  正狮陶瓷智能客服系统 - 一键启动
REM  启动链路：MySQL容器 -> 建材业务服务(18081) -> 客服后端(18082) -> 前端(5173)
REM  每一步都确认就绪后才继续；全部就绪才打开浏览器，
REM  避免出现"前端页面打开了但服务还不能用"的情况。
REM ============================================================

REM ---------- 路径配置（以脚本所在目录为项目根目录） ----------
set "ROOT=%~dp0"
set "DOCKER_DIR=%ROOT%external\docker"
set "ECOMM_DIR=%ROOT%external\ecommerce-service-backend"
set "FRONTEND_DIR=%ROOT%external\customer-service-frontend"

set "MYSQL_CONTAINER=customer-service-mysql"
rem 从 docker/.env 读取数据库口令（口令不入库，模板见 .env.example）
if exist "%DOCKER_DIR%\.env" for /f "usebackq tokens=1,* delims==" %%a in ("%DOCKER_DIR%\.env") do set "%%a=%%b"
set "ECOMM_URL=http://127.0.0.1:18081/health"
set "FRONTEND_URL=http://127.0.0.1:5173"
set "FRONTEND_MARK=src/main.js"

echo ============================================================
echo   正狮陶瓷智能客服系统 - 一键启动
echo ============================================================
echo.

REM ---------- 第1步：环境检查 ----------
echo [1/6] 检查运行环境（Docker / uv / Node）...
docker info >nul 2>&1
if errorlevel 1 call :ensure_docker
if errorlevel 1 (
    echo [错误] Docker 不可用，请手动启动 Docker Desktop 后重试。
    pause
    exit /b 1
)
where uv >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 uv，请先安装：https://docs.astral.sh/uv/
    pause
    exit /b 1
)
where node >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 Node.js，请先安装 Node.js 18 及以上版本。
    pause
    exit /b 1
)
where curl >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 curl，本脚本需要 curl 做健康检查。
    pause
    exit /b 1
)
echo     环境检查通过
echo.

REM ---------- 第2步：启动 MySQL 容器 ----------
echo [2/6] 启动 MySQL 容器（customer-service-mysql）...
docker ps --format "{{.Names}}" | findstr /c:"%MYSQL_CONTAINER%" >nul 2>&1
if errorlevel 1 (
    netstat -ano | findstr ":3306 " | findstr "LISTENING" >nul 2>&1
    if not errorlevel 1 (
        echo [错误] 3306 端口已被其他程序占用，MySQL 容器无法启动。
        echo         请执行  netstat -ano ^| findstr :3306  查看占用进程并处理后重试。
        pause
        exit /b 1
    )
)
docker compose -f "%DOCKER_DIR%\docker-compose.yml" up -d
if errorlevel 1 (
    echo [错误] MySQL 容器启动失败，请检查 Docker Desktop 状态及上方日志。
    pause
    exit /b 1
)
echo     等待 MySQL 就绪（首次初始化约需 30~60 秒）...
set /a _wait=0
:wait_mysql
docker exec %MYSQL_CONTAINER% mysqladmin ping -uroot -p%MYSQL_ROOT_PASSWORD% >nul 2>&1
if not errorlevel 1 goto mysql_ready
timeout /t 2 /nobreak >nul
set /a _wait+=2
if %_wait% geq 120 (
    echo [错误] MySQL 等待超时（120秒）。请在 Docker Desktop 中查看该容器日志。
    pause
    exit /b 1
)
goto wait_mysql
:mysql_ready
echo     MySQL 已就绪
echo.

REM ---------- 第3步：启动建材业务服务（18081） ----------
echo [3/6] 启动建材业务服务（:18081）...
call :probe "%ECOMM_URL%"
if not errorlevel 1 (
    echo     建材业务服务已在运行，跳过启动
) else (
    cd /d "%ECOMM_DIR%"
    start "建材业务服务 18081" cmd /k uv run python main.py
    cd /d "%ROOT%"
    call :wait_http "%ECOMM_URL%" 60 "建材业务服务"
    if errorlevel 1 (
        echo [提示] 请查看"建材业务服务 18081"窗口中的错误日志。
        pause
        exit /b 1
    )
)
echo     建材业务服务已就绪
echo.

REM ---------- 第4步：启动客服后端（18082） ----------
echo [4/6] 启动客服后端（:18082）...
call :probe "http://127.0.0.1:18082/docs"
if not errorlevel 1 (
    echo     客服后端已在运行，跳过启动
) else (
    cd /d "%ROOT%"
    start "客服后端 18082" cmd /k uv run python main.py
    call :wait_http "http://127.0.0.1:18082/openapi.json" 90 "客服后端"
    if errorlevel 1 (
        echo [提示] 请查看"客服后端 18082"窗口中的错误日志（常见原因：MySQL 未就绪、.env 配置缺失）。
        pause
        exit /b 1
    )
)
REM 深度校验：确认后端能真正连上数据库，否则页面能开但聊天/历史功能不可用
call :wait_http "http://127.0.0.1:18082/api/chat/history?sender_id=__start_probe__" 30 "客服后端数据库链路"
if errorlevel 1 (
    echo [错误] 后端已启动但数据库链路不通，聊天与历史记录功能将不可用。
    echo         请确认 MySQL 容器已就绪、.env 中 DATABASE_URL 配置正确。
    pause
    exit /b 1
)
echo     客服后端已就绪（已通过数据库链路校验）
echo.

REM ---------- 第5步：启动前端页面服务（5173） ----------
echo [5/6] 启动前端页面服务（:5173）...
call :probe_frontend
if not errorlevel 1 (
    echo     前端服务已在运行，跳过启动
) else (
    cd /d "%FRONTEND_DIR%"
    start "前端页面 5173" cmd /k npm run dev -- --strictPort
    cd /d "%ROOT%"
    call :wait_frontend 90
    if errorlevel 1 (
        echo [提示] 请查看"前端页面 5173"窗口中的错误日志（常见原因：5173 端口被占用）。
        pause
        exit /b 1
    )
)
echo     前端页面服务已就绪
echo.

REM ---------- 第6步：打开浏览器 ----------
echo [6/6] 全部服务就绪，正在打开前端页面...
start "" "%FRONTEND_URL%"
echo.
echo ============================================================
echo   启动完成！
echo   - 前端页面 : http://127.0.0.1:5173
echo   - 客服后端 : http://127.0.0.1:18082/docs
echo   - 建材服务 : http://127.0.0.1:18081/docs
echo.
echo   三个服务窗口请保持开启，关闭对应窗口即停止该服务。
echo   本窗口可以关闭。
echo ============================================================
pause
exit /b 0

REM ============================================================
REM  子程序区
REM ============================================================

:ensure_docker
REM Docker 未运行时尝试自动启动 Docker Desktop 并等待守护进程就绪
echo     Docker 未运行，尝试启动 Docker Desktop...
if exist "C:\Program Files\Docker\Docker\Docker Desktop.exe" (
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
) else (
    echo     未找到 Docker Desktop，请手动启动它。
)
set /a _wait=0
:ed_loop
docker info >nul 2>&1
if not errorlevel 1 exit /b 0
timeout /t 3 /nobreak >nul
set /a _wait+=3
if %_wait% geq 90 exit /b 1
goto ed_loop

:probe
REM 单次 HTTP 探测：%~1=URL，返回 200 则 errorlevel 为 0
for /f "delims=" %%c in ('curl -s -o nul -w "%%{http_code}" --max-time 2 "%~1"') do set "_code=%%c"
if "%_code%"=="200" exit /b 0
exit /b 1

:wait_http
REM 循环等待 HTTP 200：%~1=URL  %~2=超时秒数  %~3=服务名
set /a _deadline=%~2
set /a _elapsed=0
set /a _dot=0
:wh_loop
for /f "delims=" %%c in ('curl -s -o nul -w "%%{http_code}" --max-time 3 "%~1"') do set "_code=%%c"
if "%_code%"=="200" exit /b 0
set /a _dot+=2
if %_dot% geq 10 (
    echo     等待 %~3 启动中...（已等待 %_elapsed% 秒，状态码 %_code%）
    set /a _dot=0
)
timeout /t 2 /nobreak >nul
set /a _elapsed+=2
if %_elapsed% geq %_deadline% (
    echo [错误] %~3 未能在 %~2 秒内就绪（当前状态码: %_code%）
    exit /b 1
)
goto wh_loop

:probe_frontend
REM 前端探测：HTTP 200 且页面包含项目标记，防止撞上同端口的其他服务
del /q "%TEMP%\cs_frontend_probe.html" >nul 2>&1
curl -s --max-time 2 -o "%TEMP%\cs_frontend_probe.html" "%FRONTEND_URL%" >nul 2>&1
if exist "%TEMP%\cs_frontend_probe.html" (
    findstr /c:"%FRONTEND_MARK%" "%TEMP%\cs_frontend_probe.html" >nul 2>&1
    if not errorlevel 1 exit /b 0
)
exit /b 1

:wait_frontend
REM 循环等待前端就绪：%~1=超时秒数
set /a _deadline=%~1
set /a _elapsed=0
set /a _dot=0
:wf_loop
del /q "%TEMP%\cs_frontend_probe.html" >nul 2>&1
curl -s --max-time 3 -o "%TEMP%\cs_frontend_probe.html" "%FRONTEND_URL%" >nul 2>&1
if exist "%TEMP%\cs_frontend_probe.html" (
    findstr /c:"%FRONTEND_MARK%" "%TEMP%\cs_frontend_probe.html" >nul 2>&1
    if not errorlevel 1 exit /b 0
)
set /a _dot+=2
if %_dot% geq 10 (
    echo     等待前端页面服务启动中...（已等待 %_elapsed% 秒）
    set /a _dot=0
)
timeout /t 2 /nobreak >nul
set /a _elapsed+=2
if %_elapsed% geq %_deadline% (
    echo [错误] 前端页面服务未能在 %~1 秒内就绪。
    exit /b 1
)
goto wf_loop
