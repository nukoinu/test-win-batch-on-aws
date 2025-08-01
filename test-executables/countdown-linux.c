#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <sys/types.h>
#include <pthread.h>
#include "i18n-linux.h"

int main(int argc, char *argv[]) {
    // i18n初期化
    init_i18n(argc, argv);
    
    // 言語関連の引数を除外して実際の引数を取得
    char* filtered_argv[10]; // 十分な数を確保
    int filtered_argc = filter_args(argc, argv, filtered_argv);
    
    // 引数チェック
    if (filtered_argc != 2) {
        printf(_(MSG_USAGE), filtered_argv[0]);
        printf(_(MSG_EXAMPLE), filtered_argv[0]);
        return 1;
    }
    
    int seconds = atoi(filtered_argv[1]);
    if (seconds <= 0) {
        printf(_(MSG_ERROR_POSITIVE));
        return 1;
    }
    
    // プロセス情報を表示
    pid_t processId = getpid();
    pthread_t threadId = pthread_self();
    
    // 現在時刻を取得
    time_t now;
    time(&now);
    struct tm *local = localtime(&now);
    
    printf(_(MSG_TEST_PROGRAM_HEADER));
    printf(_(MSG_START_TIME), 
           local->tm_year + 1900, local->tm_mon + 1, local->tm_mday,
           local->tm_hour, local->tm_min, local->tm_sec);
    printf(_(MSG_PROCESS_ID), (long)processId);
    printf(_(MSG_THREAD_ID), (unsigned long)threadId);
    printf(_(MSG_COUNTDOWN_START), seconds);
    printf(_(MSG_SEPARATOR));
    
    // カウントダウン実行
    for (int i = seconds; i > 0; i--) {
        printf(_(MSG_REMAINING_TIME), i, (long)processId);
        fflush(stdout);  // バッファをフラッシュ
        sleep(1);        // 1秒待機
    }
    
    // 終了時刻を表示
    time(&now);
    local = localtime(&now);
    printf(_(MSG_SEPARATOR));
    printf(_(MSG_END_TIME), 
           local->tm_year + 1900, local->tm_mon + 1, local->tm_mday,
           local->tm_hour, local->tm_min, local->tm_sec);
    printf(_(MSG_PROCESS_COMPLETE), (long)processId);
    
    return 0;
}
