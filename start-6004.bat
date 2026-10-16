@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  正狮陶瓷智能客服系统 - 一键启动（端口统一版）
REM
REM  启动链路：MySQL容器(6110) -> 客服后端(6004) -> 前端(6015)
REM
REM  与旧版 start-all.bat 的区别：
REM    1. 端口按「项目端口规划」统一到 6000 段
REM    2. 用 PowerShell 做健康检查（旧版依赖 curl，本机未安装）
REM    3. 每一步都会等待就绪，失败时打印排查提示
REM ============================================================

set "ROOT=%~dp0"
set "DOCKER_DIR=%ROOT%external\docker"
set "FRONTEND_DIR=%ROOT%external\customer-service-frontend"

set "MYSQL_CONTAINER=customer-service-mysql"
set "MYSQL_PORT=6110"
set "APP_PORT=6004"
set "FRONTEND_PORT=6015"

rem 从 docker/.env 读取数据库口令
if exist "%DOCKER_DIR%\.env" for /f "usebackq tokens=1,* delims==" %%a in ("%DOCKER_DIR%\.env") do set "%%a=%%b"

echo ============================================================
echo   正狮陶瓷智能客服系统 - 一键启动
echo   MySQL:%MYSQL_PORT%  后端:%APP_PORT%  前端:%FRONTEND_PORT%
echo ============================================================
echo.

REM ---------- [1/4] 环境检查 ----------
echo [1/4] 检查运行环境...
docker info >nul 2>&1
if errorlevel 1 (
    echo   [错误] Docker 未运行，请先启动 Docker Desktop。
    pause & exit /b 1
)
where uv >nul 2>&1
if errorlevel 1 (
    echo   [错误] 未找到 uv，请安装：https://docs.astral.sh/uv/
    pause & exit /b 1
)
where node >nul 2>&1
if errorlevel 1 (
    echo   [错误] 未找到 Node.js，请安装 Node.js 18+
    pause & exit /b 1
)
echo   环境检查通过
echo.

REM ---------- [2/4] MySQL 容器 ----------
echo [2/4] 启动 MySQL 容器（对外端口 %MYSQL_PORT%）...
pushd "%DOCKER_DIR%"
docker compose up -d >nul 2>&1
popd

echo   等待 MySQL 就绪...
set "MYSQL_READY="
for /l %%i in (1,1,60) do (
    if not defined MYSQL_READY (
        docker exec %MYSQL_CONTAINER% mysqladmin ping -uroot -p%MYSQL_ROOT_PASSWORD% >nul 2>&1
        if not errorlevel 1 set "MYSQL_READY=1"
        if not defined MYSQL_READY timeout /t 2 >nul
    )
)
if not defined MYSQL_READY (
    echo   [错误] MySQL 未在 120 秒内就绪。排查：
    echo          docker logs %MYSQL_CONTAINER%
    echo          netstat -ano ^| findstr ":%MYSQL_PORT% "
    pause & exit /b 1
)
echo   MySQL 就绪
echo.

REM ---------- [3/4] 后端 ----------
echo [3/4] 启动客服后端（端口 %APP_PORT%）...
netstat -ano | findstr ":%APP_PORT% " | findstr "LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo   端口 %APP_PORT% 已在监听，跳过启动
) else (
    start "客服后端 %APP_PORT%" cmd /k "uv run python main.py"
)

echo   等待后端就绪（最多 90 秒）...
set "API_READY="
for /l %%i in (1,1,45) do (
    if not defined API_READY (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%health_probe.ps1" -Url "http://127.0.0.1:%APP_PORT%/openapi.json" >nul 2>&1
        if not errorlevel 1 set "API_READY=1"
        if not defined API_READY timeout /t 2 >nul
    )
)
if not defined API_READY (
    echo   [错误] 后端未就绪。排查：
    echo          - 查看「客服后端 %APP_PORT%」窗口的报错
    echo          - 确认 .env 的 DATABASE_URL 端口为 %MYSQL_PORT%
    pause & exit /b 1
)
echo   后端就绪
echo.

REM ---------- [4/4] 前端（可选） ----------
echo [4/4] 启动前端（端口 %FRONTEND_PORT%）...
if not exist "%FRONTEND_DIR%\package.json" (
    echo   未找到前端目录，跳过。若只需 API 文档可直接访问：
    echo     http://127.0.0.1:%APP_PORT%/docs
    goto :done
)
netstat -ano | findstr ":%FRONTEND_PORT% " | findstr "LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo   端口 %FRONTEND_PORT% 已在监听，跳过启动
) else (
    start "客服前端 %FRONTEND_PORT%" cmd /k "cd /d "%FRONTEND_DIR%" && npm run dev -- --port %FRONTEND_PORT% --strictPort"
)

:done
echo.
echo ============================================================
echo   启动完成
echo     API 文档 : http://127.0.0.1:%APP_PORT%/docs
echo     前端页面 : http://127.0.0.1:%FRONTEND_PORT%
echo     MySQL    : 127.0.0.1:%MYSQL_PORT%
echo ============================================================
echo.
echo 提示：关闭本窗口不会停止服务；停止服务请关掉对应 cmd 窗口，
echo       停止数据库执行：docker stop %MYSQL_CONTAINER%
echo.
pause
