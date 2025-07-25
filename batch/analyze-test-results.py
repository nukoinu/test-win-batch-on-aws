#!/usr/bin/env python3
"""
AWS Batch 多重度テストの結果を分析するスクリプト
"""

import json
import os
import sys
import glob
from datetime import datetime
import statistics

# オプショナルな依存関係
try:
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False

try:
    import pandas as pd
    HAS_PANDAS = True
except ImportError:
    HAS_PANDAS = False


def load_test_results(results_dir):
    """
    テスト結果JSONファイルを読み込み
    
    Args:
        results_dir (str): 結果ディレクトリのパス
        
    Returns:
        list: テスト結果のリスト
    """
    results = []
    json_files = glob.glob(os.path.join(results_dir, "*.json"))
    
    for file_path in sorted(json_files):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                data['filename'] = os.path.basename(file_path)
                results.append(data)
        except Exception as e:
            print(f"⚠️  ファイル読み込みエラー {file_path}: {e}")
    
    return results


def analyze_submission_performance(results):
    """
    ジョブ送信パフォーマンスを分析
    
    Args:
        results (list): テスト結果のリスト
        
    Returns:
        dict: 分析結果
    """
    analysis = {}
    
    for result in results:
        test_name = result['filename'].replace('.json', '')
        
        successful_jobs = [j for j in result['jobs'] if j['status'] == 'SUBMITTED']
        submit_durations = [j.get('submitDuration', 0) for j in successful_jobs]
        
        if submit_durations:
            analysis[test_name] = {
                'total_jobs': result['totalJobs'],
                'successful_jobs': len(successful_jobs),
                'failed_jobs': result['failedJobs'],
                'success_rate': len(successful_jobs) / result['totalJobs'] * 100,
                'avg_submit_time': statistics.mean(submit_durations),
                'median_submit_time': statistics.median(submit_durations),
                'max_submit_time': max(submit_durations),
                'min_submit_time': min(submit_durations),
                'std_submit_time': statistics.stdev(submit_durations) if len(submit_durations) > 1 else 0
            }
    
    return analysis


def generate_performance_report(analysis, output_file):
    """
    パフォーマンスレポートを生成
    
    Args:
        analysis (dict): 分析結果
        output_file (str): 出力ファイルパス
    """
    report_lines = [
        "# AWS Batch 多重度テスト結果レポート",
        f"生成日時: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "",
        "## テスト結果サマリー",
        ""
    ]
    
    # テーブルヘッダー
    report_lines.extend([
        "| テストケース | ジョブ数 | 成功率 | 平均送信時間 | 中央値送信時間 | 最大送信時間 | 標準偏差 |",
        "|-------------|----------|--------|-------------|---------------|-------------|----------|"
    ])
    
    # テスト結果をテーブル形式で追加
    for test_name, data in analysis.items():
        row = (
            f"| {test_name} | {data['total_jobs']} | "
            f"{data['success_rate']:.1f}% | "
            f"{data['avg_submit_time']:.3f}s | "
            f"{data['median_submit_time']:.3f}s | "
            f"{data['max_submit_time']:.3f}s | "
            f"{data['std_submit_time']:.3f}s |"
        )
        report_lines.append(row)
    
    report_lines.extend([
        "",
        "## 詳細分析",
        ""
    ])
    
    # 詳細分析
    for test_name, data in analysis.items():
        report_lines.extend([
            f"### {test_name}",
            f"- **総ジョブ数**: {data['total_jobs']}",
            f"- **成功ジョブ数**: {data['successful_jobs']}",
            f"- **失敗ジョブ数**: {data['failed_jobs']}",
            f"- **成功率**: {data['success_rate']:.1f}%",
            f"- **平均送信時間**: {data['avg_submit_time']:.3f}秒",
            f"- **送信時間中央値**: {data['median_submit_time']:.3f}秒",
            f"- **最大送信時間**: {data['max_submit_time']:.3f}秒",
            f"- **最小送信時間**: {data['min_submit_time']:.3f}秒",
            f"- **標準偏差**: {data['std_submit_time']:.3f}秒",
            ""
        ])
    
    # パフォーマンス傾向の分析
    job_counts = [data['total_jobs'] for data in analysis.values()]
    avg_times = [data['avg_submit_time'] for data in analysis.values()]
    
    if len(job_counts) > 1:
        report_lines.extend([
            "## パフォーマンス傾向",
            "",
            "### 多重度による影響の評価:",
            ""
        ])
        
        # 最小と最大のパフォーマンスを比較
        min_jobs_idx = job_counts.index(min(job_counts))
        max_jobs_idx = job_counts.index(max(job_counts))
        
        min_jobs_data = list(analysis.values())[min_jobs_idx]
        max_jobs_data = list(analysis.values())[max_jobs_idx]
        
        performance_ratio = max_jobs_data['avg_submit_time'] / min_jobs_data['avg_submit_time']
        
        report_lines.extend([
            f"- **最小多重度** ({min_jobs_data['total_jobs']}ジョブ): {min_jobs_data['avg_submit_time']:.3f}秒",
            f"- **最大多重度** ({max_jobs_data['total_jobs']}ジョブ): {max_jobs_data['avg_submit_time']:.3f}秒",
            f"- **パフォーマンス比**: {performance_ratio:.2f}x",
            ""
        ])
        
        if performance_ratio > 1.5:
            report_lines.append("⚠️ **警告**: 高い多重度により送信時間が50%以上増加しています。")
        elif performance_ratio > 1.2:
            report_lines.append("⚡ **注意**: 多重度により送信時間が増加していますが、許容範囲内です。")
        else:
            report_lines.append("✅ **良好**: 多重度による大きなパフォーマンス劣化は見られません。")
    
    # レポートをファイルに書き込み
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(report_lines))
    
    print(f"📊 パフォーマンスレポートを生成しました: {output_file}")


def create_performance_charts(analysis, output_dir):
    """
    パフォーマンスチャートを作成
    
    Args:
        analysis (dict): 分析結果
        output_dir (str): 出力ディレクトリ
    """
    if not HAS_MATPLOTLIB:
        print("⚠️  matplotlib がインストールされていないため、チャートをスキップします")
        return
        
    try:
        
        # データを準備
        test_names = list(analysis.keys())
        job_counts = [analysis[name]['total_jobs'] for name in test_names]
        avg_times = [analysis[name]['avg_submit_time'] for name in test_names]
        success_rates = [analysis[name]['success_rate'] for name in test_names]
        
        # 図1: ジョブ数 vs 平均送信時間
        plt.figure(figsize=(12, 8))
        
        plt.subplot(2, 2, 1)
        plt.plot(job_counts, avg_times, 'bo-', linewidth=2, markersize=8)
        plt.xlabel('ジョブ数')
        plt.ylabel('平均送信時間 (秒)')
        plt.title('ジョブ数 vs 平均送信時間')
        plt.grid(True, alpha=0.3)
        
        # 図2: ジョブ数 vs 成功率
        plt.subplot(2, 2, 2)
        plt.plot(job_counts, success_rates, 'go-', linewidth=2, markersize=8)
        plt.xlabel('ジョブ数')
        plt.ylabel('成功率 (%)')
        plt.title('ジョブ数 vs 成功率')
        plt.ylim(0, 105)
        plt.grid(True, alpha=0.3)
        
        # 図3: 送信時間の分布
        plt.subplot(2, 2, 3)
        plt.bar(range(len(test_names)), avg_times, color='skyblue', alpha=0.7)
        plt.xlabel('テストケース')
        plt.ylabel('平均送信時間 (秒)')
        plt.title('テストケース別 平均送信時間')
        plt.xticks(range(len(test_names)), [name.split('-')[-1] for name in test_names], rotation=45)
        plt.grid(True, alpha=0.3)
        
        # 図4: パフォーマンス効率
        plt.subplot(2, 2, 4)
        efficiency = [job_counts[i] / avg_times[i] for i in range(len(job_counts))]
        plt.plot(job_counts, efficiency, 'ro-', linewidth=2, markersize=8)
        plt.xlabel('ジョブ数')
        plt.ylabel('効率 (ジョブ/秒)')
        plt.title('スループット効率')
        plt.grid(True, alpha=0.3)
        
        plt.tight_layout()
        chart_file = os.path.join(output_dir, 'performance-charts.png')
        plt.savefig(chart_file, dpi=300, bbox_inches='tight')
        print(f"📈 パフォーマンスチャートを保存しました: {chart_file}")
        
    except ImportError:
        print("⚠️  matplotlib がインストールされていないため、チャートをスキップします")
    except Exception as e:
        print(f"⚠️  チャート作成エラー: {e}")


def main():
    if len(sys.argv) != 2:
        print("使用法: python3 analyze-test-results.py <results_directory>")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    
    if not os.path.exists(results_dir):
        print(f"❌ 結果ディレクトリが見つかりません: {results_dir}")
        sys.exit(1)
    
    print(f"📊 テスト結果を分析中: {results_dir}")
    
    # テスト結果を読み込み
    results = load_test_results(results_dir)
    
    if not results:
        print("❌ 分析対象のJSONファイルが見つかりません")
        sys.exit(1)
    
    print(f"📄 {len(results)}個のテスト結果ファイルを読み込みました")
    
    # パフォーマンスを分析
    analysis = analyze_submission_performance(results)
    
    # レポートを生成
    report_file = os.path.join(results_dir, 'performance-report.md')
    generate_performance_report(analysis, report_file)
    
    # チャートを作成
    create_performance_charts(analysis, results_dir)
    
    print("\n🎉 分析完了！")
    print(f"   レポート: {report_file}")
    print(f"   チャート: {os.path.join(results_dir, 'performance-charts.png')}")


if __name__ == "__main__":
    main()
