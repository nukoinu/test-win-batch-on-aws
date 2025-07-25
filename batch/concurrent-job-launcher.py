#!/usr/bin/env python3
"""
AWS Batchで複数のジョブを同時起動して多重度の影響を検証するスクリプト
"""

import boto3
import json
import time
import argparse
import threading
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import uuid


class BatchJobLauncher:
    def __init__(self, job_queue, job_definition, region='us-west-2'):
        """
        Args:
            job_queue (str): AWS Batch ジョブキュー名
            job_definition (str): AWS Batch ジョブ定義名
            region (str): AWSリージョン
        """
        self.batch_client = boto3.client('batch', region_name=region)
        self.job_queue = job_queue
        self.job_definition = job_definition
        self.region = region
        
    def submit_single_job(self, job_suffix, countdown_seconds=30, job_params=None):
        """
        単一のBatchジョブを送信
        
        Args:
            job_suffix (str): ジョブ名のサフィックス
            countdown_seconds (int): カウントダウン秒数
            job_params (dict): 追加のジョブパラメータ
            
        Returns:
            dict: ジョブ送信結果
        """
        job_name = f"concurrent-test-{job_suffix}-{int(time.time())}"
        
        # デフォルトのジョブパラメータ
        default_params = {
            'jobName': job_name,
            'jobQueue': self.job_queue,
            'jobDefinition': self.job_definition,
            'parameters': {
                'countdownSeconds': str(countdown_seconds)
            }
        }
        
        # 追加パラメータをマージ
        if job_params:
            default_params.update(job_params)
            
        try:
            start_time = datetime.now()
            response = self.batch_client.submit_job(**default_params)
            end_time = datetime.now()
            
            job_info = {
                'jobId': response['jobId'],
                'jobName': response['jobName'],
                'submissionTime': start_time.isoformat(),
                'submitDuration': (end_time - start_time).total_seconds(),
                'countdownSeconds': countdown_seconds,
                'status': 'SUBMITTED'
            }
            
            print(f"✓ ジョブ送信完了: {job_name} (ID: {response['jobId']})")
            return job_info
            
        except Exception as e:
            error_info = {
                'jobName': job_name,
                'error': str(e),
                'submissionTime': datetime.now().isoformat(),
                'status': 'FAILED_TO_SUBMIT'
            }
            print(f"✗ ジョブ送信失敗: {job_name} - {str(e)}")
            return error_info
    
    def submit_concurrent_jobs(self, num_jobs, countdown_seconds=30, max_workers=10):
        """
        複数のジョブを同時送信
        
        Args:
            num_jobs (int): 送信するジョブ数
            countdown_seconds (int): 各ジョブのカウントダウン秒数
            max_workers (int): 同時実行するワーカー数
            
        Returns:
            list: ジョブ送信結果のリスト
        """
        print(f"🚀 {num_jobs}個のジョブを同時送信開始...")
        print(f"   ジョブキュー: {self.job_queue}")
        print(f"   ジョブ定義: {self.job_definition}")
        print(f"   カウントダウン: {countdown_seconds}秒")
        print(f"   最大ワーカー数: {max_workers}")
        print("-" * 50)
        
        start_time = datetime.now()
        job_results = []
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # 全ジョブを同時送信
            future_to_job = {
                executor.submit(self.submit_single_job, f"job{i:03d}", countdown_seconds): i 
                for i in range(1, num_jobs + 1)
            }
            
            # 結果を収集
            for future in as_completed(future_to_job):
                job_result = future.result()
                job_results.append(job_result)
        
        end_time = datetime.now()
        total_duration = (end_time - start_time).total_seconds()
        
        print("-" * 50)
        print(f"📊 送信完了: {len(job_results)}個のジョブ")
        print(f"   総送信時間: {total_duration:.2f}秒")
        print(f"   平均送信時間: {total_duration/len(job_results):.2f}秒/ジョブ")
        
        # 送信成功・失敗の統計
        successful = [j for j in job_results if j['status'] == 'SUBMITTED']
        failed = [j for j in job_results if j['status'] == 'FAILED_TO_SUBMIT']
        
        print(f"   成功: {len(successful)}個")
        print(f"   失敗: {len(failed)}個")
        
        return job_results
    
    def monitor_jobs(self, job_results, check_interval=10):
        """
        送信されたジョブの状態を監視
        
        Args:
            job_results (list): submit_concurrent_jobsの戻り値
            check_interval (int): チェック間隔（秒）
        """
        successful_jobs = [j for j in job_results if j['status'] == 'SUBMITTED']
        if not successful_jobs:
            print("監視対象のジョブがありません")
            return
        
        job_ids = [j['jobId'] for j in successful_jobs]
        print(f"📈 {len(job_ids)}個のジョブを監視開始...")
        
        completed_jobs = set()
        
        while len(completed_jobs) < len(job_ids):
            try:
                # ジョブ状態を取得
                response = self.batch_client.describe_jobs(jobs=job_ids)
                
                current_time = datetime.now().strftime("%H:%M:%S")
                print(f"\n[{current_time}] ジョブ状態:")
                
                status_count = {}
                
                for job in response['jobs']:
                    job_id = job['jobId']
                    job_name = job['jobName']
                    status = job['jobStatus']
                    
                    # 状態をカウント
                    status_count[status] = status_count.get(status, 0) + 1
                    
                    # 完了したジョブを記録
                    if status in ['SUCCEEDED', 'FAILED'] and job_id not in completed_jobs:
                        completed_jobs.add(job_id)
                        
                        if status == 'SUCCEEDED':
                            print(f"  ✓ {job_name}: {status}")
                        else:
                            print(f"  ✗ {job_name}: {status}")
                            if 'statusReason' in job:
                                print(f"    理由: {job['statusReason']}")
                    elif status in ['SUBMITTED', 'PENDING', 'RUNNABLE', 'STARTING', 'RUNNING']:
                        print(f"  ⏳ {job_name}: {status}")
                
                # 状態サマリーを表示
                print(f"  状態サマリー: {dict(status_count)}")
                print(f"  完了: {len(completed_jobs)}/{len(job_ids)}")
                
                if len(completed_jobs) < len(job_ids):
                    time.sleep(check_interval)
                    
            except Exception as e:
                print(f"監視エラー: {str(e)}")
                time.sleep(check_interval)
        
        print("\n🎉 全ジョブが完了しました！")
    
    def save_results(self, job_results, output_file):
        """
        結果をJSONファイルに保存
        
        Args:
            job_results (list): ジョブ送信結果
            output_file (str): 出力ファイルパス
        """
        result_data = {
            'timestamp': datetime.now().isoformat(),
            'jobQueue': self.job_queue,
            'jobDefinition': self.job_definition,
            'totalJobs': len(job_results),
            'successfulJobs': len([j for j in job_results if j['status'] == 'SUBMITTED']),
            'failedJobs': len([j for j in job_results if j['status'] == 'FAILED_TO_SUBMIT']),
            'jobs': job_results
        }
        
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(result_data, f, ensure_ascii=False, indent=2)
        
        print(f"💾 結果を保存しました: {output_file}")


def main():
    parser = argparse.ArgumentParser(description='AWS Batchジョブ同時起動テスト')
    parser.add_argument('--job-queue', required=True, help='Batchジョブキュー名')
    parser.add_argument('--job-definition', required=True, help='Batchジョブ定義名')
    parser.add_argument('--num-jobs', type=int, default=5, help='起動するジョブ数 (デフォルト: 5)')
    parser.add_argument('--countdown', type=int, default=30, help='カウントダウン秒数 (デフォルト: 30)')
    parser.add_argument('--max-workers', type=int, default=10, help='最大ワーカー数 (デフォルト: 10)')
    parser.add_argument('--region', default='us-west-2', help='AWSリージョン (デフォルト: us-west-2)')
    parser.add_argument('--output', help='結果出力ファイル (JSON)')
    parser.add_argument('--monitor', action='store_true', help='ジョブ実行を監視する')
    parser.add_argument('--monitor-interval', type=int, default=10, help='監視間隔（秒）')
    
    args = parser.parse_args()
    
    # Batch Job Launcherを初期化
    launcher = BatchJobLauncher(
        job_queue=args.job_queue,
        job_definition=args.job_definition,
        region=args.region
    )
    
    # ジョブを同時送信
    job_results = launcher.submit_concurrent_jobs(
        num_jobs=args.num_jobs,
        countdown_seconds=args.countdown,
        max_workers=args.max_workers
    )
    
    # 結果を保存
    if args.output:
        launcher.save_results(job_results, args.output)
    
    # 監視オプション
    if args.monitor:
        launcher.monitor_jobs(job_results, args.monitor_interval)


if __name__ == "__main__":
    main()
