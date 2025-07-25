#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
#include <time.h>

int main(int argc, char *argv[]) {
    // 引数チェック
    if (argc != 2) {
        printf("使用法: %s <秒数>\n", argv[0]);
        printf("例: %s 10\n", argv[0]);
        return 1;
    }
    
    int seconds = atoi(argv[1]);
    if (seconds <= 0) {
        printf("エラー: 正の整数を指定してください\n");
        return 1;
    }
    
    // プロセス情報を表示
    DWORD processId = GetCurrentProcessId();
    DWORD threadId = GetCurrentThreadId();
    
    // 現在時刻を取得
    time_t now;
    time(&now);
    struct tm *local = localtime(&now);
    
    printf("=== Windows テストプログラム ===\n");
    printf("開始時刻: %04d-%02d-%02d %02d:%02d:%02d\n", 
           local->tm_year + 1900, local->tm_mon + 1, local->tm_mday,
           local->tm_hour, local->tm_min, local->tm_sec);
    printf("プロセスID: %lu\n", processId);
    printf("スレッドID: %lu\n", threadId);
    printf("カウントダウン開始: %d秒\n", seconds);
    printf("-----------------------------\n");
    
    // カウントダウン実行
    for (int i = seconds; i > 0; i--) {
        printf("残り時間: %d秒 (PID: %lu)\n", i, processId);
        fflush(stdout);  // バッファをフラッシュ
        Sleep(1000);     // 1秒待機
    }
    
    // 終了時刻を表示
    time(&now);
    local = localtime(&now);
    printf("-----------------------------\n");
    printf("終了時刻: %04d-%02d-%02d %02d:%02d:%02d\n", 
           local->tm_year + 1900, local->tm_mon + 1, local->tm_mday,
           local->tm_hour, local->tm_min, local->tm_sec);
    printf("プロセス完了 (PID: %lu)\n", processId);
    
    return 0;
}
