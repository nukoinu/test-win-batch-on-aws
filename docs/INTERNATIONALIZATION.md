# 国際化対応 (Internationalization)

このプロジェクトは日本語と英語の両方に対応しています。

## 言語設定

### 自動検出
システムのロケール設定に基づいて自動的に言語が選択されます：
- Windows: システムのロケール設定
- Linux/macOS: `LANG` 環境変数

### 手動指定
コマンドライン引数で言語を明示的に指定できます：

```bash
# 英語で実行
countdown.exe --lang=en 10
countdown.exe --english 10
countdown.exe -l en 10

# 日本語で実行
countdown.exe --lang=ja 10
countdown.exe --japanese 10
countdown.exe -l ja 10
```

## C言語プログラム (countdown.c)

### 機能
- システム言語の自動検出
- コマンドライン引数による言語指定
- 軽量なヘッダーオンリーの実装

### 使用例

```c
// プログラム内での言語設定
#include "i18n.h"

int main(int argc, char* argv[]) {
    // i18n初期化（システム言語またはコマンドライン引数から自動検出）
    init_i18n(argc, argv);
    
    // メッセージの取得
    printf(_(MSG_USAGE), argv[0]);
    
    return 0;
}
```

### サポートされるメッセージ
- 使用方法の説明
- エラーメッセージ
- プロセス実行情報
- 時刻表示
- カウントダウンメッセージ

## ビルド方法

### Windows
```cmd
build-i18n.bat
```

### Linux/macOS
```bash
./build-i18n.sh
```

## ファイル構成

```
test-executables/
├── countdown.c          # メインプログラム（国際化対応済み）
├── i18n.h              # 国際化ヘッダーファイル
├── build-i18n.bat      # Windows用ビルドスクリプト
└── build-i18n.sh       # Linux/macOS用ビルドスクリプト

i18n/
├── ja.json             # 日本語メッセージ
└── en.json             # 英語メッセージ
```

## 今後の拡張

### Python スクリプト対応
Python スクリプトの国際化については、以下のような実装が可能です：

```python
from i18n import t, set_language

# 言語設定
set_language('ja')  # または 'en'

# メッセージ取得
print(t('job.submission_started', num_jobs=5))
```

### 新しい言語の追加
1. `i18n/` ディレクトリに新しい言語ファイルを追加（例: `fr.json`）
2. `i18n.h` のメッセージテーブルに新しい言語を追加
3. 言語検出ロジックを更新

### 環境変数による言語設定
```bash
# 環境変数で言語を指定
export COUNTDOWN_LANG=ja
countdown.exe 10

export COUNTDOWN_LANG=en  
countdown.exe 10
```
