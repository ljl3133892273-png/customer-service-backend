# /engine/dialogue_engine.py

import time

from clarify.responder import ClarifyResponder
from domain.state import DialogueState
from domain.messages import UserMessage, ProcessResult, BotMessage, MessageType
from plan.models import ClarifyReason
from plan.turn_planner import TurnPlanner
from plan.turn_validator import TurnPlanValidator
from task.command.models import Command, SetSlotsCommand
from task.flow.flows import FlowsList
from task.flow.steps import CollectFlowStep
from task.handler import TaskHandler, ChitChatHandler, KnowledgeHandler


class DialogueEngine:

    def __init__(
            self,
            turn_planner: TurnPlanner,
            task_handler: TaskHandler,
            knowledge_handler: KnowledgeHandler,
            chitchat_handler: ChitChatHandler,
            clarify_responder: ClarifyResponder,
            turn_plan_validator: TurnPlanValidator
    ) -> None:
        pass
        self.turn_planner = turn_planner
        self.task_handler = task_handler
        self.knowledge_handler = knowledge_handler
        self.chitchat_handler = chitchat_handler
        self.clarify_responder = clarify_responder
        self.turn_plan_validator = turn_plan_validator

    async def process_message(self, dialogue_state: DialogueState,
                              user_message: UserMessage) -> ProcessResult:

        # TODO (用户的消息---->LLM路由(三条轨道的某一条) 执行某一条)

        # 1. 准备会话
        self._prepare_session(dialogue_state)

        # 2. 开启本轮turn
        self._begin_turn(dialogue_state, user_message)

        # 3. 按消息类型分流
        if user_message.type is MessageType.TEXT:
            messages = await self._handle_text_message(dialogue_state)
        else:
            # 对象消息
            dialogue_state.set_focused_object(user_message.object)
            messages = await self._handle_object_message(message=user_message, state=dialogue_state)

        # 4. 把本轮回复写入turn
        dialogue_state.pending_turn.bot_messages.extend(messages)
        # 提交:turn进入session历史
        dialogue_state.commit_turn()

        # 5. 组装返回结果
        return ProcessResult(
            sender_id=user_message.sender_id,
            message_id=user_message.message_id,
            messages=messages,
        )

    def _prepare_session(self, dialogue_state: DialogueState) -> None:
        """
        决定"这条消息属于哪一段会话"
        第一步:准备会话
        :param dialogue_state:
        :return:
        """

        # 1. 获取当前会话
        session = dialogue_state.current_session()

        # 2. 如果当前会话不存在，则创建一个会话
        if session is None:
            dialogue_state.start_session()
            return

        # 3. 判断会话是否超时
        now = time.time()

        # 空闲超过 1 小时才算超时，开新会话；否则沿用当前会话
        if now - session.last_activity_at > 60 * 60:
            # 关闭会话
            dialogue_state.close_current_session()
            # 重置运行时状态
            dialogue_state.reset_runtime_state_for_new_session()
            # 创建会话
            dialogue_state.start_session()

        else:
            # 更新会话
            session.last_activity_at = now

    def _begin_turn(self, dialogue_state: DialogueState, user_message: UserMessage) -> None:
        """
        第二部:开启一个turn
        :param dialogue_state:
        :param user_message:
        :return:
        """

        dialogue_state.begin_turn(user_message)

    async def _handle_text_message(self, dialogue_state: DialogueState) -> list[BotMessage]:
        # 1. 调用llm生成本轮计划
        turn_plan = await self.turn_planner.predict(dialogue_state, self.task_handler.flows)

        # 2. 防止幻觉校验
        # TODO

        # 3. 按轨道分发
        if turn_plan.task is not None:
            return await self.task_handler.handle(
                commands=turn_plan.task.commands,
                state=dialogue_state,
            )

        elif turn_plan.knowledge is not None:
            # TODO(知识轨道后续实现，先兜底防崩)
            return [BotMessage(text="知识咨询功能建设中，当前可帮你查订单、查物流或申请退款。")]

        else:
            # 闲聊轨道
            return await self.chitchat_handler.handle(state = dialogue_state)


    async def _handle_object_message(
            self,
            message: UserMessage,
            state: DialogueState,
    ) -> list[BotMessage]:
        # 将对象解析成command(SetSlotsCommand)
        commands = self._resolve_object_commands(
            message=message,
            state=state,
            flows=self.task_handler.flows,
        )

        if commands:
            # 场景A: 对象能填当前槽位 -> 转成命令，推进流程
            return await self.task_handler.handle(commands=commands, state=state)

        # 没有匹配到slot，用户正在一个流程中，不打断，让流程继续
        if state.active_task is not None:
            # 场景C:在流程里但槽不匹配 -> 不打断，空明亮让流程继续
            return await self.task_handler.handle(commands=[], state=state)

        # 场景B: 没有流程 -> 澄清
        return await self.clarify_responder.respond(
            state=state,
            reason=ClarifyReason.OBJECT_REQUIRES_INTENT
        )

    def _resolve_object_commands(
            self,
            message: UserMessage,
            state: DialogueState,
            flows: FlowsList
    ) -> list[Command]:
        # 对象转命令
        message_object = message.object

        if message_object is None:
            return []

        object_type = message_object.type.strip().lower()

        if object_type == 'order':
            if self._flow_has_unfilled_collect_slot(state, flows, "order_number"):
                return [SetSlotsCommand(
                    command='set_slots',
                    slots={'order_number': message_object.id},
                )]
            return []

        if object_type == "product":
            if self._flow_has_unfilled_collect_slot(state, flows, "product_id"):
                return [SetSlotsCommand(
                    command="set_slots",
                    slots={"product_id": message_object.id},
                )]
            return []

        return []

    @staticmethod
    def _flow_has_unfilled_collect_slot(  # 能否填槽的判断
            state: DialogueState,
            flows: FlowsList,
            slot_name: str
    ) -> bool:

        """检查当前流程是否定义了名为 slot_name 的收集槽且尚未填充。"""
        active_task = state.active_task
        if active_task is None:     # 没有活跃流程
            return False

        flow = flows.get_flow_by_id(active_task.flow_id)
        if flow is None:            # 流程id查不到
            return False

        if active_task.slots.get(slot_name):
            return False            # 这个槽位已经填了

        for step in flow.steps:     # 流程里有没有收集这个槽的步骤
            if isinstance(step,CollectFlowStep) and step.slot_name == slot_name:
                return True

        return False
