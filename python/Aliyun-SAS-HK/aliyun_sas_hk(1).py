# -*- coding: utf-8 -*-
import os
import sys
import yaml
import logging
from os import path
from datetime import datetime
from typing import List, Optional

from alibabacloud_swas_open20200601.client import Client as SWASClient
from alibabacloud_tea_openapi import models as open_api_models
from alibabacloud_swas_open20200601 import models as swas_models
from alibabacloud_tea_util import models as util_models
from alibabacloud_tea_console.client import Client as ConsoleClient
from alibabacloud_tea_util.client import Client as UtilClient


class AlibabaCloudInstanceManager:
    def __init__(self, account_config: dict):
        self.config = account_config
        self.client = self.create_client()

    def create_client(self) -> SWASClient:
        # 使用 AK&SK 初始化账号 Client
        try:
            config = open_api_models.Config(
                access_key_id=self.config['access_key_id'],
                access_key_secret=self.config['access_key_secret']
            )
            config.endpoint = f'swas.{self.config["region_id"]}.aliyuncs.com'
            return SWASClient(config)
        except KeyError as e:
            raise ValueError(f"配置文件中缺少必要的键: {e}")

    @staticmethod
    def get_current_utc_time() -> str:
        # 获取当前UTC时间的字符串表示
        return datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')

    def create_instance(self) -> dict:
        # 创建实例并处理结果，返回结果信息
        request = swas_models.CreateInstancesRequest(
            region_id=self.config['region_id'],
            image_id=self.config['image_id'],
            plan_id=self.config['plan_id'],
            period=self.config['period'],
            auto_renew=self.config['auto_renew']
        )
        runtime = util_models.RuntimeOptions()
        request_time = self.get_current_utc_time()

        result = {
            "account_name": self.config['account_name'],
            "success": False,
            "message": "",
            "instance_ids": [],
            "time": request_time
        }

        try:
            response = self.client.create_instances_with_options(request, runtime)
            ConsoleClient.log(UtilClient.to_jsonstring(response))
            instance_ids = response.body.InstanceIds
            result["success"] = True
            result["instance_ids"] = instance_ids
            result["message"] = f"抢购成功！InstanceIds: {instance_ids}"
            logging.info(result["message"])

        except Exception as error:
            error_message = getattr(error, 'message', str(error))
            recommend = getattr(error, 'data', {}).get('Recommend', '无诊断信息')
            result["message"] = f"抢购失败: {error_message}\n诊断信息: {recommend}"
            logging.error(result["message"])

        return result


def load_config(config_path: str) -> List[dict]:
    # 加载多账号配置文件并进行验证
    try:
        with open(config_path, 'r', encoding='utf-8') as file:
            config = yaml.safe_load(file)
            if 'accounts' not in config or not isinstance(config['accounts'], list):
                raise ValueError("配置文件格式不正确或缺少 'accounts' 键")
            return config['accounts']
    except yaml.YAMLError as e:
        raise ValueError(f"解析配置文件时出错: {e}")


def send_notification(success_results: List[dict], failure_results: List[dict]) -> None:
    # 发送推送通知，分开成功和失败的结果
    success_message = "成功的账号:\n" + "\n".join(
        [f"{result['account_name']} - InstanceIds: {result['instance_ids']} (时间: {result['time']})"
         for result in success_results]) if success_results else "无成功抢购"

    failure_message = "失败的账号:\n" + "\n".join(
        [f"{result['account_name']} - 错误信息: {result['message']} (时间: {result['time']})"
         for result in failure_results]) if failure_results else "无失败抢购"

    final_message = f"{success_message}\n\n{failure_message}"

    send = load_send_function()
    if callable(send):
        send("阿里云轻量抢购", final_message)
    else:
        logging.warning("通知服务不可用，以下为结果信息：")
        logging.info(final_message)


def load_send_function() -> Optional[callable]:
    # 加载外部通知服务
    cur_path = path.abspath(path.dirname(sys.argv[0]))
    notify_script = path.join(cur_path, "notify.py")

    if path.exists(notify_script):
        try:
            from notify import send
            return send
        except ImportError as e:
            logging.error(f"导入 notify 模块失败: {e}")
            return None
    else:
        logging.error(f"未找到 notify.py 文件：{notify_script}")
        return None


def setup_logging():
    # 设置日志配置，日志信息输出到控制台和文件
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler("instance_manager.log", encoding='utf-8'),
            logging.StreamHandler(sys.stdout)
        ]
    )


if __name__ == '__main__':
    setup_logging()

    try:
        config_path = path.join(path.abspath(path.dirname(__file__)), 'config.yml')
        accounts = load_config(config_path)

        success_results = []
        failure_results = []

        for account_config in accounts:
            manager = AlibabaCloudInstanceManager(account_config)
            result = manager.create_instance()
            if result["success"]:
                success_results.append(result)
            else:
                failure_results.append(result)

        send_notification(success_results, failure_results)

    except Exception as e:
        logging.critical(f"程序执行失败: {e}")