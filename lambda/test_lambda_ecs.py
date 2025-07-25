#!/usr/bin/env python3
"""
Lambda-ECS Windows Executor テストスクリプト

このスクリプトは、LambdaからECS上のWindowsコンテナでexeファイルを実行する
機能をテストするためのものです。
"""

import json
import time
import requests
import argparse
import sys
from typing import Dict, Any, Optional

def execute_windows_exe(api_endpoint: str, exe_args: list, cluster_name: str = None) -> Dict[str, Any]:
    """
    Windows EXEファイルを実行する
    
    Args:
        api_endpoint: API Gateway の実行エンドポイント
        exe_args: EXEファイルに渡す引数のリスト
        cluster_name: ECSクラスター名（オプション）
    
    Returns:
        実行結果
    """
    payload = {
        "exe_args": exe_args
    }
    
    if cluster_name:
        payload["cluster_name"] = cluster_name
    
    try:
        print(f"Executing Windows EXE with args: {exe_args}")
        response = requests.post(
            api_endpoint,
            headers={'Content-Type': 'application/json'},
            json=payload,
            timeout=30
        )
        
        response.raise_for_status()
        result = response.json()
        
        print(f"Execution started successfully!")
        print(f"Response: {json.dumps(result, indent=2)}")
        
        return result
        
    except requests.exceptions.RequestException as e:
        print(f"Error executing Windows EXE: {e}")
        if hasattr(e, 'response') and e.response:
            print(f"Response status: {e.response.status_code}")
            print(f"Response body: {e.response.text}")
        raise

def monitor_task_status(monitor_endpoint: str, task_arn: str, cluster_name: str = None) -> Dict[str, Any]:
    """
    ECSタスクのステータスを監視する
    
    Args:
        monitor_endpoint: API Gateway の監視エンドポイント
        task_arn: タスクARN
        cluster_name: ECSクラスター名（オプション）
    
    Returns:
        タスクのステータス
    """
    payload = {
        "task_arn": task_arn
    }
    
    if cluster_name:
        payload["cluster_name"] = cluster_name
    
    try:
        response = requests.post(
            monitor_endpoint,
            headers={'Content-Type': 'application/json'},
            json=payload,
            timeout=30
        )
        
        response.raise_for_status()
        result = response.json()
        
        return result
        
    except requests.exceptions.RequestException as e:
        print(f"Error monitoring task status: {e}")
        if hasattr(e, 'response') and e.response:
            print(f"Response status: {e.response.status_code}")
            print(f"Response body: {e.response.text}")
        raise

def wait_for_task_completion(monitor_endpoint: str, task_arn: str, cluster_name: str = None, 
                           max_wait_time: int = 300, check_interval: int = 10) -> Dict[str, Any]:
    """
    タスクの完了を待機する
    
    Args:
        monitor_endpoint: API Gateway の監視エンドポイント
        task_arn: タスクARN
        cluster_name: ECSクラスター名（オプション）
        max_wait_time: 最大待機時間（秒）
        check_interval: チェック間隔（秒）
    
    Returns:
        最終的なタスクステータス
    """
    start_time = time.time()
    
    print(f"Waiting for task completion (max {max_wait_time} seconds)...")
    
    while time.time() - start_time < max_wait_time:
        try:
            result = monitor_task_status(monitor_endpoint, task_arn, cluster_name)
            status_body = json.loads(result['body'])
            task_status = status_body['status']
            
            current_status = task_status['lastStatus']
            print(f"Current status: {current_status}")
            
            if current_status in ['STOPPED']:
                print("Task completed!")
                return task_status
            elif current_status in ['RUNNING']:
                print("Task is running...")
            elif current_status in ['PENDING']:
                print("Task is pending...")
            else:
                print(f"Unknown status: {current_status}")
            
            time.sleep(check_interval)
            
        except Exception as e:
            print(f"Error checking task status: {e}")
            time.sleep(check_interval)
    
    print(f"Timeout waiting for task completion (waited {max_wait_time} seconds)")
    # 最終ステータスを取得して返す
    try:
        result = monitor_task_status(monitor_endpoint, task_arn, cluster_name)
        status_body = json.loads(result['body'])
        return status_body['status']
    except:
        return None

def run_test(execute_endpoint: str, monitor_endpoint: str, exe_args: list, 
            cluster_name: str = None, wait_for_completion: bool = True) -> bool:
    """
    完全なテストを実行する
    
    Args:
        execute_endpoint: 実行エンドポイント
        monitor_endpoint: 監視エンドポイント
        exe_args: EXE引数
        cluster_name: クラスター名
        wait_for_completion: 完了を待機するかどうか
    
    Returns:
        テストが成功したかどうか
    """
    try:
        # 1. EXEファイルを実行
        print("=" * 50)
        print("Step 1: Executing Windows EXE...")
        execution_result = execute_windows_exe(execute_endpoint, exe_args, cluster_name)
        
        # タスクARNを取得
        execution_body = json.loads(execution_result['body'])
        task_arn = execution_body['taskArn']
        
        print(f"Task ARN: {task_arn}")
        
        if not wait_for_completion:
            print("Not waiting for completion as requested.")
            return True
        
        # 2. タスクの完了を待機
        print("\n" + "=" * 50)
        print("Step 2: Waiting for task completion...")
        final_status = wait_for_task_completion(monitor_endpoint, task_arn, cluster_name)
        
        if final_status:
            print("\n" + "=" * 50)
            print("Final Task Status:")
            print(json.dumps(final_status, indent=2, default=str))
            
            # 成功判定
            if final_status['lastStatus'] == 'STOPPED':
                containers = final_status.get('containers', [])
                if containers and containers[0].get('exitCode') == 0:
                    print("\n✅ Test completed successfully!")
                    return True
                else:
                    print(f"\n❌ Test failed - Container exit code: {containers[0].get('exitCode') if containers else 'Unknown'}")
                    return False
            else:
                print(f"\n❌ Test failed - Task status: {final_status['lastStatus']}")
                return False
        else:
            print("\n❌ Test failed - Could not retrieve final status")
            return False
            
    except Exception as e:
        print(f"\n❌ Test failed with exception: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description='Test Lambda-ECS Windows Executor',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic test with 10 second countdown
  python3 test_lambda_ecs.py \\
    --execute-endpoint https://api.gateway.url/prod/execute \\
    --monitor-endpoint https://api.gateway.url/prod/status \\
    --exe-args 10

  # Test with custom cluster and 30 second countdown
  python3 test_lambda_ecs.py \\
    --execute-endpoint https://api.gateway.url/prod/execute \\
    --monitor-endpoint https://api.gateway.url/prod/status \\
    --cluster-name my-windows-cluster \\
    --exe-args 30

  # Quick test without waiting for completion
  python3 test_lambda_ecs.py \\
    --execute-endpoint https://api.gateway.url/prod/execute \\
    --monitor-endpoint https://api.gateway.url/prod/status \\
    --exe-args 5 \\
    --no-wait
        """
    )
    
    parser.add_argument(
        '--execute-endpoint',
        required=True,
        help='API Gateway execute endpoint URL'
    )
    
    parser.add_argument(
        '--monitor-endpoint',
        required=True,
        help='API Gateway monitor endpoint URL'
    )
    
    parser.add_argument(
        '--exe-args',
        nargs='+',
        default=['10'],
        help='Arguments to pass to the EXE file (default: 10)'
    )
    
    parser.add_argument(
        '--cluster-name',
        help='ECS cluster name (optional)'
    )
    
    parser.add_argument(
        '--no-wait',
        action='store_true',
        help='Do not wait for task completion'
    )
    
    parser.add_argument(
        '--max-wait-time',
        type=int,
        default=300,
        help='Maximum time to wait for task completion in seconds (default: 300)'
    )
    
    args = parser.parse_args()
    
    print("Lambda-ECS Windows Executor Test")
    print("=" * 50)
    print(f"Execute Endpoint: {args.execute_endpoint}")
    print(f"Monitor Endpoint: {args.monitor_endpoint}")
    print(f"EXE Arguments: {args.exe_args}")
    print(f"Cluster Name: {args.cluster_name or 'Default'}")
    print(f"Wait for Completion: {not args.no_wait}")
    
    success = run_test(
        execute_endpoint=args.execute_endpoint,
        monitor_endpoint=args.monitor_endpoint,
        exe_args=args.exe_args,
        cluster_name=args.cluster_name,
        wait_for_completion=not args.no_wait
    )
    
    if success:
        print("\n🎉 All tests passed!")
        sys.exit(0)
    else:
        print("\n💥 Test failed!")
        sys.exit(1)

if __name__ == '__main__':
    main()
