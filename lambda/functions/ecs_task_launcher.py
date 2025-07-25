import json
import boto3
import os
import logging
from typing import Dict, Any, Optional

# ロギング設定
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS クライアント
ecs_client = boto3.client('ecs')
logs_client = boto3.client('logs')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda関数のメインハンドラー
    ECS上のWindowsコンテナでexeファイルを実行する
    
    Args:
        event: Lambdaイベント
        context: Lambdaコンテキスト
    
    Returns:
        実行結果
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # イベントから必要なパラメータを取得
        exe_args = event.get('exe_args', ['10'])  # デフォルト: 10秒カウントダウン
        cluster_name = event.get('cluster_name', os.environ.get('ECS_CLUSTER_NAME', 'windows-countdown-cluster'))
        task_definition = event.get('task_definition', os.environ.get('TASK_DEFINITION_ARN'))
        subnet_ids = event.get('subnet_ids', os.environ.get('SUBNET_IDS', '').split(','))
        security_group_ids = event.get('security_group_ids', os.environ.get('SECURITY_GROUP_IDS', '').split(','))
        
        # バリデーション
        if not task_definition:
            raise ValueError("Task definition ARN is required")
        if not subnet_ids or subnet_ids == ['']:
            raise ValueError("Subnet IDs are required")
        if not security_group_ids or security_group_ids == ['']:
            raise ValueError("Security Group IDs are required")
        
        # ECSタスクを実行
        response = run_ecs_task(
            cluster_name=cluster_name,
            task_definition=task_definition,
            exe_args=exe_args,
            subnet_ids=subnet_ids,
            security_group_ids=security_group_ids
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'ECS task started successfully',
                'taskArn': response['task_arn'],
                'taskId': response['task_id'],
                'exe_args': exe_args
            }, ensure_ascii=False)
        }
        
    except Exception as e:
        logger.error(f"Error occurred: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            }, ensure_ascii=False)
        }

def run_ecs_task(
    cluster_name: str,
    task_definition: str,
    exe_args: list,
    subnet_ids: list,
    security_group_ids: list
) -> Dict[str, str]:
    """
    ECSタスクを実行する
    
    Args:
        cluster_name: ECSクラスター名
        task_definition: タスク定義ARN
        exe_args: exeファイルに渡す引数
        subnet_ids: サブネットIDのリスト
        security_group_ids: セキュリティグループIDのリスト
    
    Returns:
        タスクARNとタスクID
    """
    try:
        # ECSタスクを起動
        response = ecs_client.run_task(
            cluster=cluster_name,
            taskDefinition=task_definition,
            launchType='EC2',
            networkConfiguration={
                'awsvpcConfiguration': {
                    'subnets': subnet_ids,
                    'securityGroups': security_group_ids,
                    'assignPublicIp': 'ENABLED'
                }
            },
            overrides={
                'containerOverrides': [
                    {
                        'name': 'windows-countdown-container',
                        'command': ['C:\\app\\countdown.exe'] + exe_args
                    }
                ]
            },
            count=1,
            tags=[
                {
                    'key': 'LaunchedBy',
                    'value': 'Lambda'
                },
                {
                    'key': 'Purpose',
                    'value': 'WindowsExeExecution'
                }
            ]
        )
        
        if response['failures']:
            raise Exception(f"Failed to start ECS task: {response['failures']}")
        
        task_arn = response['tasks'][0]['taskArn']
        task_id = task_arn.split('/')[-1]
        
        logger.info(f"ECS task started successfully: {task_arn}")
        
        return {
            'task_arn': task_arn,
            'task_id': task_id
        }
        
    except Exception as e:
        logger.error(f"Failed to run ECS task: {str(e)}")
        raise

def get_task_logs(cluster_name: str, task_arn: str, log_group_name: str) -> Optional[list]:
    """
    ECSタスクのログを取得する
    
    Args:
        cluster_name: ECSクラスター名
        task_arn: タスクARN
        log_group_name: CloudWatchログループ名
    
    Returns:
        ログエントリのリスト
    """
    try:
        task_id = task_arn.split('/')[-1]
        log_stream_name = f"windows-countdown-container/windows-countdown-container/{task_id}"
        
        response = logs_client.get_log_events(
            logGroupName=log_group_name,
            logStreamName=log_stream_name,
            startFromHead=True
        )
        
        return response['events']
        
    except Exception as e:
        logger.error(f"Failed to get task logs: {str(e)}")
        return None

def check_task_status(cluster_name: str, task_arn: str) -> Dict[str, Any]:
    """
    ECSタスクのステータスを確認する
    
    Args:
        cluster_name: ECSクラスター名
        task_arn: タスクARN
    
    Returns:
        タスクのステータス情報
    """
    try:
        response = ecs_client.describe_tasks(
            cluster=cluster_name,
            tasks=[task_arn]
        )
        
        if not response['tasks']:
            raise Exception(f"Task not found: {task_arn}")
        
        task = response['tasks'][0]
        
        return {
            'lastStatus': task['lastStatus'],
            'desiredStatus': task['desiredStatus'],
            'createdAt': task['createdAt'].isoformat() if 'createdAt' in task else None,
            'startedAt': task['startedAt'].isoformat() if 'startedAt' in task else None,
            'stoppedAt': task['stoppedAt'].isoformat() if 'stoppedAt' in task else None,
            'stopCode': task.get('stopCode'),
            'stoppedReason': task.get('stoppedReason')
        }
        
    except Exception as e:
        logger.error(f"Failed to check task status: {str(e)}")
        raise
