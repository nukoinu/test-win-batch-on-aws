@echo off
REM Windows Container ビルド・デプロイスクリプト
echo ===============================================
echo Windows EXE Docker Container Build Script
echo ===============================================

REM 環境変数設定
set ECR_REGISTRY=%1
set IMAGE_TAG=%2
set AWS_REGION=ap-northeast-1

if "%ECR_REGISTRY%"=="" (
    echo エラー: ECRレジストリURLが指定されていません
    echo 使用方法: build-windows.bat ^<ECR_REGISTRY^> [TAG]
    echo 例: build-windows.bat 123456789012.dkr.ecr.us-east-1.amazonaws.com latest
    exit /b 1
)

if "%IMAGE_TAG%"=="" (
    set IMAGE_TAG=latest
)

set FULL_IMAGE_NAME=%ECR_REGISTRY%/windows-countdown-app:%IMAGE_TAG%

echo Registry: %ECR_REGISTRY%
echo Image: %FULL_IMAGE_NAME%
echo.

REM Docker Desktop がWindows Container モードか確認
echo Step 1: Docker設定確認中...
docker version | findstr "OS/Arch:" | findstr "windows"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ⚠️ Docker Desktop がWindows Container モードではありません
    echo 以下の手順でWindows Container モードに切り替えてください:
    echo 1. Docker Desktop のシステムトレイアイコンを右クリック
    echo 2. "Switch to Windows containers..." をクリック
    echo 3. UAC確認で "はい" をクリック
    echo 4. Docker Desktop が再起動されるのを待つ
    echo.
    pause
    exit /b 1
)
echo ✅ Windows Container モード確認完了

REM EXEファイル存在確認
echo.
echo Step 2: EXEファイル確認中...
if not exist "countdown.exe" (
    echo ❌ countdown.exe が見つかりません
    echo 以下の手順でEXEファイルを作成してください:
    echo 1. MinGW-w64 をインストール
    echo 2. x86_64-w64-mingw32-gcc -o countdown.exe ..\..\test-executables\countdown.c -static
    echo 3. countdown.exe をこのディレクトリにコピー
    pause
    exit /b 1
)
echo ✅ countdown.exe 確認完了

REM Dockerイメージビルド
echo.
echo Step 3: Dockerイメージビルド中...
docker build -t windows-countdown:local -f Dockerfile.windows-native .
if %ERRORLEVEL% neq 0 (
    echo ❌ Dockerビルドに失敗しました
    pause
    exit /b 1
)
echo ✅ Dockerビルド完了

REM ローカルテスト
echo.
echo Step 4: ローカルテスト実行中...
echo テスト: 5秒間のカウントダウン
docker run --rm windows-countdown:local countdown.exe 5
if %ERRORLEVEL% neq 0 (
    echo ❌ ローカルテストに失敗しました
    pause
    exit /b 1
)
echo ✅ ローカルテスト完了

REM ECRログイン
echo.
echo Step 5: ECRログイン中...
aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %ECR_REGISTRY%
if %ERRORLEVEL% neq 0 (
    echo ❌ ECRログインに失敗しました
    echo AWS CLI が設定されているか確認してください
    pause
    exit /b 1
)
echo ✅ ECRログイン完了

REM イメージタグ付け
echo.
echo Step 6: イメージタグ付け中...
docker tag windows-countdown:local %FULL_IMAGE_NAME%
if %ERRORLEVEL% neq 0 (
    echo ❌ イメージタグ付けに失敗しました
    pause
    exit /b 1
)
echo ✅ イメージタグ付け完了

REM ECRプッシュ
echo.
echo Step 7: ECRプッシュ中...
docker push %FULL_IMAGE_NAME%
if %ERRORLEVEL% neq 0 (
    echo ❌ ECRプッシュに失敗しました
    pause
    exit /b 1
)
echo ✅ ECRプッシュ完了

REM 完了メッセージ
echo.
echo ===============================================
echo 🎉 Windows Container ビルド・デプロイ完了！
echo ===============================================
echo.
echo イメージ: %FULL_IMAGE_NAME%
echo.
echo 次のステップ:
echo 1. ECS Task Definition を作成
echo 2. AWS Batch Job Definition を作成
echo 3. 多重起動テストを実行
echo.
echo ECS Task Definition 例:
echo {
echo   "family": "windows-countdown-task",
echo   "containerDefinitions": [
echo     {
echo       "name": "countdown",
echo       "image": "%FULL_IMAGE_NAME%",
echo       "command": ["countdown.exe", "30"],
echo       "memory": 1024
echo     }
echo   ]
echo }
echo.
pause
