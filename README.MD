# Windows EXE ファイル AWS 実行検証プロジェクト

このリポジトリは、AWS上でWindowsのEXEファイルをAWS BatchやAWS Lambdaで利用可能かどうかを検証するためのリソースを管理するためのものです。

## 目的

- WindowsバイナリファイルのAWS Batch での実行可能性の検証
- WindowsバイナリファイルのAWS Lambda での実行可能性の検証
- 各サービスでの制約事項や課題の把握
- 実行パフォーマンスやコストの評価

## 検証対象

### AWS Batch
- Windows コンテナでのEXE実行
- ジョブキューとジョブ定義の設定
- 実行時間とリソース使用量の測定

### AWS Lambda
- Wine を使用したLinux環境でのWindows EXE実行
- Lambda Layer を使用したWineの配布
- 実行制限時間内での処理可能性

## リポジトリ構成

```
├── README.MD                 # このファイル
├── batch/                    # AWS Batch 関連のリソース
│   ├── docker/              # Dockerfiles
│   ├── job-definitions/     # ジョブ定義
│   └── cloudformation/      # CloudFormation テンプレート
├── lambda/                   # AWS Lambda 関連のリソース
│   ├── functions/           # Lambda 関数
│   ├── layers/              # Lambda Layer（Wine等）
│   └── cloudformation/      # CloudFormation テンプレート
├── test-executables/         # テスト用のWindows EXEファイル
└── docs/                     # 検証結果やドキュメント
```

## 検証手順

### 前提条件
- AWS CLI が設定済みであること
- Docker がインストール済みであること
- 適切なAWS権限が設定されていること

### AWS Batch での検証
1. Windows コンテナ用のECRリポジトリを作成
2. Docker イメージをビルドしてECRにプッシュ
3. ジョブ定義とジョブキューを作成
4. ジョブを実行して結果を確認

### AWS Lambda での検証
1. Wine を含むLambda Layerを作成
2. Windows EXE を実行するLambda関数をデプロイ
3. 関数を実行して結果を確認

## 制約事項

### AWS Batch
- Windows コンテナは Linux コンテナよりもリソース使用量が多い
- 起動時間が長い可能性がある

### AWS Lambda
- Wine の互換性に依存
- Lambda の実行時間制限（15分）
- メモリ制限の制約

## 参考資料

- [AWS Batch User Guide](https://docs.aws.amazon.com/batch/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Wine Documentation](https://www.winehq.org/documentation)

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。