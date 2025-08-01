# Amazon Linux 2 用 Makefile

CC = gcc
CFLAGS = -Wall -Wextra -std=c99
LDFLAGS = -lpthread
TARGET = countdown-linux
SOURCE = countdown-linux.c
HEADER = i18n-linux.h

# デフォルトターゲット
all: $(TARGET)

# メインターゲット
$(TARGET): $(SOURCE) $(HEADER)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCE) $(LDFLAGS)

# インストール（システムワイド）
install: $(TARGET)
	sudo cp $(TARGET) /usr/local/bin/
	sudo chmod 755 /usr/local/bin/$(TARGET)

# テスト実行
test: $(TARGET)
	@echo "=== テスト実行 ==="
	@echo "デフォルト言語:"
	./$(TARGET) 3
	@echo ""
	@echo "英語:"
	./$(TARGET) --lang=en 3
	@echo ""
	@echo "日本語:"
	./$(TARGET) --lang=ja 3

# クリーンアップ
clean:
	rm -f $(TARGET)

# Amazon Linux 2 パッケージのインストール
install-deps:
	sudo yum update -y
	sudo yum install -y gcc make

# 開発用依存関係のインストール
install-dev-deps: install-deps
	sudo yum install -y \
		git \
		tar \
		gzip \
		which \
		vim

# Docker イメージビルド
docker-build:
	docker build -t countdown-amazonlinux:latest -f ../docker/Dockerfile.amazonlinux .

# Docker テスト実行
docker-test:
	docker run --rm countdown-amazonlinux:latest ./countdown-linux 5

# ヘルプ
help:
	@echo "Amazon Linux 2 用 Makefile"
	@echo ""
	@echo "利用可能なターゲット:"
	@echo "  all              - プログラムをビルド"
	@echo "  $(TARGET)        - プログラムをビルド"
	@echo "  install          - システムワイドにインストール"
	@echo "  test             - テスト実行"
	@echo "  clean            - ビルド成果物を削除"
	@echo "  install-deps     - 基本依存関係をインストール"
	@echo "  install-dev-deps - 開発用依存関係をインストール"
	@echo "  docker-build     - Docker イメージをビルド"
	@echo "  docker-test      - Docker テスト実行"
	@echo "  help             - このヘルプを表示"
	@echo ""
	@echo "使用例:"
	@echo "  make                    # ビルド"
	@echo "  make test               # テスト実行"
	@echo "  make install-deps       # 依存関係インストール"
	@echo "  make docker-build       # Docker ビルド"

.PHONY: all install test clean install-deps install-dev-deps docker-build docker-test help
