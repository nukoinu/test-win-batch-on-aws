# 検証テストシーケンス図

このドキュメントでは、AWS上でのWindows EXEファイル実行検証のテストシーケンスをMermaid形式で表現しています。

## 1. AWS Batch 多重度検証テストシーケンス

```mermaid
sequenceDiagram
    participant User as テスター
    participant Script as concurrent-job-launcher.py
    participant Batch as AWS Batch
    participant ECS as ECS クラスター
    participant Container as Windows コンテナ
    participant Monitor as analyze-test-results.py
    participant CW as CloudWatch

    Note over User, CW: AWS Batch 多重度検証フロー

    User->>Script: テスト実行 (ジョブ数, 秒数指定)
    Script->>Script: ThreadPoolExecutor初期化
    
    loop 指定されたジョブ数分並行実行
        Script->>+Batch: submit_job() (ジョブキューに送信)
        Batch->>+ECS: ジョブをECSクラスターにスケジュール
        ECS->>+Container: Windowsコンテナ起動
        Container->>Container: countdown.exe実行開始
        Batch-->>Script: ジョブID返却
        Script->>Script: ジョブ情報記録 (送信時間, ID等)
    end

    Script->>CW: ジョブ送信完了ログ出力
    
    loop ジョブ実行監視
        Container->>Container: countdown実行中 (指定秒数)
        Container->>CW: 実行ログ出力
        ECS->>Batch: ジョブステータス更新
        Script->>Batch: describe_jobs() (ステータス確認)
        Batch-->>Script: ジョブステータス返却
    end

    Container->>Container: countdown.exe完了
    Container->>-ECS: コンテナ終了
    ECS->>-Batch: ジョブ完了通知
    Batch->>-Script: ジョブ完了ステータス

    Script->>Monitor: テスト結果データ出力 (JSON)
    User->>Monitor: analyze-test-results.py実行
    Monitor->>CW: CloudWatchログ取得
    Monitor->>Monitor: 成功率・実行時間分析
    Monitor->>User: 分析結果・グラフ出力
```

## 2. Lambda + ECS 実行検証テストシーケンス

```mermaid
sequenceDiagram
    participant Client as クライアント
    participant APIGW as API Gateway
    participant Launcher as ecs-task-launcher
    participant Monitor as ecs-task-monitor
    participant ECS as ECS Service
    participant Task as ECS Task
    participant Container as Windows コンテナ
    participant CW as CloudWatch Logs

    Note over Client, CW: Lambda + ECS 実行検証フロー

    Client->>+APIGW: POST /execute (exe_args, cluster_name)
    APIGW->>+Launcher: Lambda関数呼び出し
    
    Launcher->>Launcher: パラメータバリデーション
    Launcher->>+ECS: run_task() (タスク定義指定)
    ECS->>+Task: Windows ECSタスク起動
    Task->>+Container: Windowsコンテナ起動
    
    ECS-->>Launcher: taskArn返却
    Launcher-->>APIGW: タスクARN・ID返却
    APIGW-->>-Client: 起動成功レスポンス (taskId)

    Container->>Container: countdown.exe実行開始
    Container->>CW: 実行ログ出力
    
    Note over Client, Container: タスク監視フェーズ

    Client->>+APIGW: GET /status/{taskId}
    APIGW->>+Monitor: ecs-task-monitor呼び出し
    Monitor->>ECS: describe_tasks() (ステータス確認)
    ECS-->>Monitor: タスクステータス返却
    Monitor->>CW: CloudWatchログ取得
    Monitor-->>APIGW: ステータス・ログ返却
    APIGW-->>-Client: 実行状況レスポンス

    loop 実行完了まで監視
        Container->>Container: countdown実行中
        Container->>CW: リアルタイムログ出力
        Client->>APIGW: ステータス確認 (ポーリング)
        APIGW->>Monitor: 監視関数呼び出し
        Monitor->>ECS: タスクステータス確認
        Monitor-->>Client: 現在ステータス返却
    end

    Container->>Container: countdown.exe完了
    Container->>CW: 完了ログ出力
    Container->>-Task: コンテナ終了
    Task->>-ECS: タスク完了

    Client->>APIGW: 最終ステータス確認
    APIGW->>Monitor: 最終結果取得
    Monitor->>CW: 完了ログ・実行時間取得
    Monitor-->>Client: 完了結果・ログ返却
```

## 3. 包括的テスト検証フローシーケンス

```mermaid
sequenceDiagram
    participant Tester as テスト実行者
    participant Setup as セットアップスクリプト
    participant BatchTest as Batch多重度テスト
    participant LambdaTest as Lambda機能テスト
    participant Analysis as 結果分析
    participant Report as レポート生成

    Note over Tester, Report: 包括的検証テストフロー

    Tester->>+Setup: ./setup.sh実行
    Setup->>Setup: AWS環境確認
    Setup->>Setup: 必要なリソース作成確認
    Setup->>Setup: Python依存関係インストール
    Setup-->>-Tester: セットアップ完了

    par AWS Batch検証
        Tester->>+BatchTest: run-concurrency-tests.sh実行
        BatchTest->>BatchTest: 単一ジョブテスト (1-5-10-20ジョブ)
        BatchTest->>BatchTest: 多重度テスト実行
        BatchTest->>Analysis: テスト結果データ保存
        BatchTest-->>-Tester: Batch検証完了
    and Lambda+ECS検証
        Tester->>+LambdaTest: test_lambda_ecs.py実行
        LambdaTest->>LambdaTest: API Gateway経由テスト
        LambdaTest->>LambdaTest: 直接Lambda呼び出しテスト
        LambdaTest->>LambdaTest: エラーハンドリングテスト
        LambdaTest->>Analysis: テスト結果データ保存
        LambdaTest-->>-Tester: Lambda検証完了
    end

    Tester->>+Analysis: analyze-test-results.py実行
    Analysis->>Analysis: Batchテスト結果分析
    Analysis->>Analysis: Lambdaテスト結果分析
    Analysis->>Analysis: パフォーマンス比較分析
    Analysis->>Analysis: コスト分析
    Analysis->>+Report: 分析結果・グラフ生成
    Report->>Report: 成功率レポート
    Report->>Report: 実行時間分析レポート
    Report->>Report: リソース使用量レポート
    Report->>Report: 推奨事項生成
    Report-->>-Analysis: レポート完成
    Analysis-->>-Tester: 包括的分析結果提供

    Note over Tester: 検証完了・意思決定支援データ取得
```

## 4. エラーハンドリング・例外フローシーケンス

```mermaid
sequenceDiagram
    participant Test as テストスクリプト
    participant AWS as AWSサービス
    participant Monitor as 監視・ログ
    participant Alert as アラート機能

    Note over Test, Alert: エラーハンドリングフロー

    alt 正常実行
        Test->>+AWS: ジョブ/タスク実行要求
        AWS-->>-Test: 成功レスポンス
        Test->>Monitor: 正常実行ログ記録
    else AWS API制限エラー
        Test->>+AWS: ジョブ/タスク実行要求
        AWS-->>-Test: ThrottlingException
        Test->>Test: 指数バックオフ再試行
        Test->>Monitor: 再試行ログ記録
        Test->>+AWS: 再実行要求
        AWS-->>-Test: 再実行レスポンス
    else リソース不足エラー
        Test->>+AWS: ジョブ/タスク実行要求
        AWS-->>-Test: InsufficientCapacityException
        Test->>Alert: リソース不足アラート
        Test->>Monitor: リソース不足ログ記録
        Test->>Test: テスト一時停止・待機
    else 認証・権限エラー
        Test->>+AWS: ジョブ/タスク実行要求
        AWS-->>-Test: AccessDeniedException
        Test->>Alert: 権限エラーアラート
        Test->>Monitor: 権限エラーログ記録
        Test->>Test: テスト中断
    else タイムアウトエラー
        Test->>+AWS: ジョブ/タスク実行要求
        AWS-->>-Test: TimeoutException
        Test->>Test: タイムアウト回数記録
        Test->>Monitor: タイムアウトログ記録
        Test->>Test: 設定見直し提案
    else 予期しないエラー
        Test->>+AWS: ジョブ/タスク実行要求
        AWS-->>-Test: UnknownException
        Test->>Alert: 予期しないエラーアラート
        Test->>Monitor: 詳細エラーログ記録
        Test->>Test: デバッグ情報収集
    end

    Test->>Monitor: 最終実行結果記録

    Note over Test, Alert: エラー分析・改善提案自動生成
```

## シーケンス図の説明

### 1. AWS Batch 多重度検証
- 複数ジョブの並行送信とパフォーマンス測定
- ThreadPoolExecutorによる効率的な並行処理
- CloudWatchログによる実行状況監視

### 2. Lambda + ECS 実行検証
- RESTful API経由でのWindowsコンテナ実行
- リアルタイムステータス監視
- CloudWatchログによる詳細ログ収集

### 3. 包括的テスト検証
- 両アプローチの並行テスト実行
- 結果の自動分析・比較
- 意思決定支援データの生成

### 4. エラーハンドリング
- 各種AWS例外の適切な処理
- 自動再試行・回復メカニズム
- 詳細なエラー分析・ログ記録
