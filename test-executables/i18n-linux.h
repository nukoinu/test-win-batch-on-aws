#ifndef I18N_LINUX_H
#define I18N_LINUX_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <locale.h>
#include <langinfo.h>

// 言語設定
typedef enum {
    LANG_EN = 0,
    LANG_JA = 1
} Language;

// メッセージID
typedef enum {
    MSG_USAGE = 0,
    MSG_EXAMPLE,
    MSG_ERROR_POSITIVE,
    MSG_TEST_PROGRAM_HEADER,
    MSG_START_TIME,
    MSG_PROCESS_ID,
    MSG_THREAD_ID,
    MSG_COUNTDOWN_START,
    MSG_SEPARATOR,
    MSG_REMAINING_TIME,
    MSG_END_TIME,
    MSG_PROCESS_COMPLETE,
    MSG_COUNT
} MessageId;

// メッセージテーブル
static const char* messages[2][MSG_COUNT] = {
    // English messages
    {
        "Usage: %s <seconds>\n",                                    // MSG_USAGE
        "Example: %s 10\n",                                        // MSG_EXAMPLE
        "Error: Please specify a positive integer\n",              // MSG_ERROR_POSITIVE
        "=== Linux Test Program ===\n",                            // MSG_TEST_PROGRAM_HEADER
        "Start time: %04d-%02d-%02d %02d:%02d:%02d\n",             // MSG_START_TIME
        "Process ID: %ld\n",                                       // MSG_PROCESS_ID
        "Thread ID: %lu\n",                                        // MSG_THREAD_ID
        "Countdown started: %d seconds\n",                         // MSG_COUNTDOWN_START
        "-----------------------------\n",                         // MSG_SEPARATOR
        "Remaining time: %d seconds (PID: %ld)\n",                 // MSG_REMAINING_TIME
        "End time: %04d-%02d-%02d %02d:%02d:%02d\n",               // MSG_END_TIME
        "Process completed (PID: %ld)\n"                           // MSG_PROCESS_COMPLETE
    },
    // Japanese messages
    {
        "使用法: %s <秒数>\n",                                        // MSG_USAGE
        "例: %s 10\n",                                              // MSG_EXAMPLE
        "エラー: 正の整数を指定してください\n",                            // MSG_ERROR_POSITIVE
        "=== Linux テストプログラム ===\n",                            // MSG_TEST_PROGRAM_HEADER
        "開始時刻: %04d-%02d-%02d %02d:%02d:%02d\n",                 // MSG_START_TIME
        "プロセスID: %ld\n",                                         // MSG_PROCESS_ID
        "スレッドID: %lu\n",                                         // MSG_THREAD_ID
        "カウントダウン開始: %d秒\n",                                    // MSG_COUNTDOWN_START
        "-----------------------------\n",                          // MSG_SEPARATOR
        "残り時間: %d秒 (PID: %ld)\n",                               // MSG_REMAINING_TIME
        "終了時刻: %04d-%02d-%02d %02d:%02d:%02d\n",                 // MSG_END_TIME
        "プロセス完了 (PID: %ld)\n"                                   // MSG_PROCESS_COMPLETE
    }
};

// グローバル言語設定
static Language current_language = LANG_EN;

// 言語を検出する関数
static Language detect_system_language() {
    // 環境変数から言語を検出
    char* lang = getenv("LANG");
    char* lc_all = getenv("LC_ALL");
    char* lc_messages = getenv("LC_MESSAGES");
    
    // LC_ALLが設定されている場合はそれを優先
    if (lc_all && strstr(lc_all, "ja")) {
        return LANG_JA;
    }
    
    // LC_MESSAGESが設定されている場合
    if (lc_messages && strstr(lc_messages, "ja")) {
        return LANG_JA;
    }
    
    // LANGから検出
    if (lang && strstr(lang, "ja")) {
        return LANG_JA;
    }
    
    return LANG_EN; // デフォルトは英語
}

// コマンドライン引数から言語を検出
static Language detect_language_from_args(int argc, char* argv[]) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--lang=ja") == 0 || strcmp(argv[i], "-l") == 0) {
            if (i + 1 < argc && strcmp(argv[i + 1], "ja") == 0) {
                return LANG_JA;
            }
        }
        if (strcmp(argv[i], "--lang=en") == 0) {
            return LANG_EN;
        }
        if (strcmp(argv[i], "--japanese") == 0) {
            return LANG_JA;
        }
        if (strcmp(argv[i], "--english") == 0) {
            return LANG_EN;
        }
    }
    
    // コマンドライン引数で指定されていない場合はシステム言語を検出
    return detect_system_language();
}

// 言語設定を初期化
static void init_i18n(int argc, char* argv[]) {
    // ロケールを設定
    setlocale(LC_ALL, "");
    current_language = detect_language_from_args(argc, argv);
}

// 言語を設定
static void set_language(Language lang) {
    current_language = lang;
}

// メッセージを取得
static const char* get_message(MessageId msg_id) {
    if (msg_id >= MSG_COUNT) {
        return "Invalid message ID";
    }
    return messages[current_language][msg_id];
}

// ショートハンド関数
static const char* _(MessageId msg_id) {
    return get_message(msg_id);
}

// 言語関連の引数を除外して実際の引数を取得
static int filter_args(int argc, char* argv[], char** filtered_argv) {
    int filtered_argc = 0;
    for (int i = 0; i < argc; i++) {
        // 言語関連の引数をスキップ
        if (strcmp(argv[i], "--lang=ja") == 0 || 
            strcmp(argv[i], "--lang=en") == 0 ||
            strcmp(argv[i], "--japanese") == 0 || 
            strcmp(argv[i], "--english") == 0) {
            continue;
        }
        if (strcmp(argv[i], "-l") == 0) {
            // 次の引数もスキップ
            if (i + 1 < argc && (strcmp(argv[i + 1], "ja") == 0 || strcmp(argv[i + 1], "en") == 0)) {
                i++; // 次の引数もスキップ
            }
            continue;
        }
        
        filtered_argv[filtered_argc] = argv[i];
        filtered_argc++;
    }
    return filtered_argc;
}

#endif // I18N_LINUX_H
