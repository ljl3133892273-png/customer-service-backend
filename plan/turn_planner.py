# /plan/turn_planner.py
''''''

'''
`TurnPlanner` 的职责：把当前对话状态喂给 LLM，让 LLM 输出一个 `TurnPlan`。
'''

from langchain_core.output_parsers import JsonOutputParser
from langchain_core.prompts import  PromptTemplate
from typing import Dict, Any
from dataclasses import asdict
from prompts.loader import load_prompt
import json

from infrastructure.llm import llm
from prompts.history_builder import HistoryBuilder
from domain.state import DialogueState
from plan.models import TurnPlan
from task.flow.flows import FlowsList


class TurnPlanner:
    """
    意图分析器
    作用：根据任务自然语言 调用LLM 分析轨道类型
    """

    async def predict(self, state: DialogueState, flows: FlowsList) -> TurnPlan:
        '''
        :param state:当前对话状态（含历史、活跃任务、聚焦对象等）
        :param flows:系统支持的所有流程（告诉 LLM 有哪些业务可办)
        :return:
        '''

        # 1. 构建提示词  整理成给 LLM 的提示词变量
        inputs_prompt = self._build_prompt_inputs(state, flows)

        # 2. 调用LLM模型    拿提示词变量调用LLM，把输出解析成 `TurnPlan`
        turn_plan = await  self._predict_from_prompt_inputs(inputs_prompt)

        return turn_plan

    def _build_prompt_inputs(self, state: DialogueState, flows_list: FlowsList) -> Dict[str, Any]:
        '''
        构建提示词输入参数
        :param state:
        :param flows_list:
        :return:
        '''

        # 1. 用户消息
        user_msg = HistoryBuilder._render_user_message(state.pending_turn.user_message)

        # 2. 历史对话(当前session的turns:后10轮：最近的10轮) 。历史对话取多少 取哪些：动态策略
        current_conversation = HistoryBuilder.build(state.current_session().turns[-10:])

        # 3. 当前激活任务(业务任务)
        active_task_json = json.dumps(
            state.active_task.model_dump(mode='json'),
            ensure_ascii=False
        ) if state.active_task is not None else None

        # 4. 中断任务
        interrupted_tasks_json = json.dumps(
            [paused_task.model_dump(mode='json') for paused_task in state.paused_tasks],
            ensure_ascii=False
        )

        # 5. 页面点击卡片获取的信息
        focused_object_json = json.dumps(
            state.focused_object.model_dump(mode='json')) if state.focused_object is not None else None

        # 6. 流程清单
        # available_flows_json=[{} for flow in flows_list.flows]

        available_flows_json = json.dumps(
            {"flows": [{k: v for k, v in flow.model_dump().items() if k != "steps"} for flow in flows_list.flows]},
            ensure_ascii=False
        )

        return {
            "user_message": user_msg,
            "current_conversation": current_conversation,
            "active_task_json": active_task_json,
            "interrupted_tasks_json": interrupted_tasks_json,
            "focused_object_json": focused_object_json,
            "available_flows_json": available_flows_json,
            "knowledge_intents_json": ""
        }  # 返回一个字典，一共 7个字段，每个都会被填进 prompt 模板的某个 `{{ }}` 占位符。

    async def _predict_from_prompt_inputs(self, inputs_prompt: Dict[str, Any]) -> TurnPlan:
        '''
        1. 加载提示词模板
        2. 格式化模版
        3. 调用模型
        :param inputs_prompt:
        :return:
        '''

        prompt_template_text = load_prompt('turn_plan')

        prompt_template = PromptTemplate.from_template(template=prompt_template_text, template_format="jinja2")

        chain = prompt_template | llm | JsonOutputParser()

        llm_response_dict: Dict[str, Any] = await chain.ainvoke(inputs_prompt)

        return TurnPlan.from_dict(llm_response_dict)
