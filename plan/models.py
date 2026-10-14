# itljl/plan/models.py
# 三个字段不能用同一种类型,得各自定义一个数据模型来承载各自的信息。

import json
from task.command.models import Command
from pydantic import BaseModel
from enum import Enum


class TaskTurnPlan(BaseModel):
    commands: list[Command] = []  # 命令

    @classmethod
    def from_dict(cls, data: dict) -> 'TaskTurnPlan':
        return cls(commands=[Command.from_dict(command) for command in data['commands']])


class KnowledgeTurnPlan(BaseModel):
    intents: list[str] = []  # 意图

    @classmethod
    def from_dict(cls, data: dict) -> 'KnowledgeTurnPlan':
        return cls(intents=data['intents'])


class ChitchatTurnPlan(BaseModel):
    pass


class ClarifyReason(str, Enum):
    MISSING_TRACK = "missing_track" # 三个都为 null，没判断出任何方向
    MULTIPLE_TRACKS = "multiple_tracks" # 同时命中多个轨道，但引擎一次只能执行一个
    MISSING_TASK_COMMANDS = "missing_task_commands" # task 轨道，但 commands 为空
    MISSING_KNOWLEDGE_INTENT = "missing_knowledge_intent"   # knowledge 轨道，但 intents 为空
    MISSING_FOCUSED_OBJECT = "missing_focused_object"   # 知识意图需要聚焦对象，但当前没有
    OBJECT_REQUIRES_INTENT = "object_requires_intent"   # 用户只发了对象，没说要干嘛
    INVALID_TASK_COMMANDS = "invalid_task_commands" # commands 里有不认识的命令类型
    MULTIPLE_TASK_FLOWS = "multiple_task_flows" # 一次出现多个 `start_flow`，同时想开好几个流程
    UNKNOWN_TASK_FLOW = "unknown_task_flow" # `start_flow` 指定的 flow 在系统里不存在（典型幻觉）


class TurnPlanValidationResult(BaseModel):
    valid: bool  # 是否有效
    reason: ClarifyReason | None = None  # 无效时的原因


class TurnPlan(BaseModel):
    '''
    本轮对话的规划结果
    '''

    task: TaskTurnPlan | None = None  # 业务任务的轨道
    knowledge: KnowledgeTurnPlan | None = None  # 信息咨询业务轨道
    chitchat: ChitchatTurnPlan | None = None  # 闲聊业务轨道

    @classmethod
    def from_dict(cls, data: dict) -> 'TurnPlan':
        return cls(
            task=TaskTurnPlan.from_dict(data['task']) if data.get('task') is not None else None,
            knowledge=KnowledgeTurnPlan.from_dict(data['knowledge']) if data.get('knowledge') is not None else None,
            chitchat=ChitchatTurnPlan() if data.get('chitchat') is not None else None,
        )


if __name__ == '__main__':
    json_str1 = """
    {
      "task": {
        "commands": [
          {"command": "start_flow", "flow": "refund_request"}
        ]
      },
      "knowledge": null,
      "chitchat": null
    }
    """

    # 转成dict
    turn_plan1 = TurnPlan.from_dict(json.loads(json_str1))
    print(turn_plan1)

    json_str2 = """
    {
      "task": {
        "commands": [
          {"command": "set_slots", "slots": {"order_number": "A001"}}
        ]
      },
      "knowledge": null,
      "chitchat": null
    }
    """
    # 转成dict
    turn_plan2 = TurnPlan.from_dict(json.loads(json_str2))
    print(turn_plan2)
