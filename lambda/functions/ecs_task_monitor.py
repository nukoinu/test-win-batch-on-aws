import json
import boto3
import os
import logging
from typing import Dict, Any

# ロギング設定
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS クライアント
ecs_client = boto3.client('ecs')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    ECSタスクのステータスを監視し、結果を取得するLambda関数
    
    Args:
        event: Lambdaイベント（task_arnが含まれる）
        context: Lambdaコンテキスト
    
    Returns:
        タスクのステータスと結果
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # イベントから必要なパラメータを取得
        task_arn = event.get('task_arn')
        cluster_name = event.get('cluster_name', os.environ.get('ECS_CLUSTER_NAME', 'windows-countdown-cluster'))
        
        if not task_arn:
            raise ValueError("task_arn is required")
        
        # タスクのステータスを確認
        task_status = check_task_status(cluster_name, task_arn)
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'taskArn': task_arn,
                'status': task_status
            }, ensure_ascii=False, default=str)
        }
        
        return response
        
    except Exception as e:
        logger.error(f"Error occurred: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            }, ensure_ascii=False)
        }

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
            'taskArn': task_arn,
            'lastStatus': task['lastStatus'],
            'desiredStatus': task['desiredStatus'],
            'createdAt': task['createdAt'].isoformat() if 'createdAt' in task else None,
            'startedAt': task['startedAt'].isoformat() if 'startedAt' in task else None,
            'stoppedAt': task['stoppedAt'].isoformat() if 'stoppedAt' in task else None,
            'stopCode': task.get('stopCode'),
            'stoppedReason': task.get('stoppedReason'),
            'containers': [
                {
                    'name': container['name'],
                    'lastStatus': container['lastStatus'],
                    'exitCode': container.get('exitCode'),
                    'reason': container.get('reason')
                }
                for container in task['containers']
            ]
        }
        
    except Exception as e:
        logger.error(f"Failed to check task status: {str(e)}")
        raise
