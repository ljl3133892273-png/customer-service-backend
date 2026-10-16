# /prompts/history_builder.py
''''''
from api.schemas import ChatObject, HistoryMessage

'''
`HistoryBuilder`的作用：把消息对象渲染成文本
'''

from typing import List, Dict, Any
from domain.state import Turn
from domain.messages import UserMessage, BotMessage, FocusedObject, MessageType


class HistoryBuilder:
    '''
    1. 将用户消息的UserMessage对象序列化为字符串---->"USER: 我准备查询订单信息"
    2. 将历史对话的Q(UserMessage)A(BotMessage)对象序列化为字符串："USER: 我想查询物流信息\n BOT: 好的，先提供订单编号"
    '''

    @staticmethod
    def build(turns: List[Turn]) -> str:
        '''
        构建历史对话
        :param turns:
        :return:
        '''

        msgs: List[str] = []

        for turn in turns:
            # 1. 用户消息
            user_message = turn.user_message
            user_message_str = HistoryBuilder._render_user_message(user_message)
            msgs.append(f'USER: {user_message_str}')

            # 2. 机器人回复消息
            for bot_msg in turn.bot_messages:
                bot_msg_str = HistoryBuilder._render_bot_message(bot_msg)
                msgs.append(f'BOT: {bot_msg_str}')

        return '\n'.join(msgs)

    @staticmethod
    def _render_user_message(user_message: UserMessage) -> str:
        '''
        渲染用户消息
        :param user_message:
        :return:
        '''

        # 以实际携带的内容为准，而不是只看 type 字段：
        # 请求可能声明 type=object 却没给 object，或 type=text 但带了 object，
        # 只按 type 分支会在 object 为 None 时抛 AttributeError（500）。
        if user_message.object is not None:
            return HistoryBuilder._render_obj_msg(user_message.object)
        if user_message.text is not None:
            return HistoryBuilder._render_text_msg(user_message.text)
        # 两者皆空属于非法请求，返回占位串而不是崩溃
        return ''

    @classmethod
    def _render_bot_message(cls, bot_msg: BotMessage) -> str:
        if bot_msg.text:
            return HistoryBuilder._render_text_msg(bot_msg.text)
        else:
            return HistoryBuilder._render_obj_msg(bot_msg.object)  # 基本走不到

    @staticmethod
    def _render_text_msg(text: str) -> str:
        return text.strip()

    @classmethod
    def _render_obj_msg(cls, object_msg: FocusedObject) -> str:
        '''
        id
        type
        title
        attributes
        :param object_msg:
        :return:
        "[id="对应的编号", type="订单对象 or 商品对象", title="对应的描述",attributes="price=1000 url="www.pic.com" ]"
        '''

        # 兜底：object 可能为 None（例如消息声明了对象类型却没带对象数据）
        if object_msg is None:
            return ''

        label = '订单对象' if object_msg.type == 'order' else '商品对象'
        id = object_msg.id
        title = object_msg.title
        attributes: Dict[str, Any] = object_msg.attributes or {}
        attributes_str = " ".join([f"{key}={value}" for key, value in attributes.items()])

        return f"[label={label}, id={id}, title={title}, attributes={attributes_str}]"

    @staticmethod
    def render_user_message(session_id: str, user_message: UserMessage) -> HistoryMessage:
        user_obj = ChatObject(**user_message.object.model_dump()) if user_message.object else None
        return HistoryMessage(
            session_id=session_id,
            role="user",
            text=user_message.text,
            object=user_obj,
        )

    @staticmethod
    def render_bot_messages(session_id: str, bot_messages: BotMessage) -> HistoryMessage:
        bot_obj = ChatObject(**bot_messages.object.model_dump()) if bot_messages.object else None
        return HistoryMessage(
            session_id=session_id,
            role="bot",
            text=bot_messages.text,
            object=bot_obj,
        )

if __name__ == '__main__':
    """
    测试 HistoryBuilder 的 build 方法
    """

    from domain.state import Turn
    from domain.messages import UserMessage, BotMessage, FocusedObject, MessageType


    def test_build_single_text_turn():
        """测试单轮纯文本对话"""
        # 创建用户消息
        user_msg = UserMessage(
            sender_id="user_001",
            message_id="msg_001",
            type=MessageType.TEXT,
            text="我想查询订单信息"
        )

        # 创建机器人回复
        bot_msg1 = BotMessage(text="你好")
        bot_msg2 = BotMessage(text="请提供订单编号")

        # 创建轮次
        turn = Turn(
            turn_id="turn_001",
            user_message=user_msg,
            bot_messages=[bot_msg1, bot_msg2]
        )

        # 构建历史对话
        result = HistoryBuilder.build([turn])
        print(f"结果:\n{result}")


    def test_build_with_object_message():
        """测试包含对象类型的消息"""
        # 用户点击了一个订单对象
        focused_obj = FocusedObject(
            id="SKU10001",
            type="order",
            title="云岩灰 亮光抛釉砖 800×800",
            attributes={"price": "68.00", "status": "待发货"}
        )

        user_msg = UserMessage(
            sender_id="user_001",
            message_id="msg_001",
            type=MessageType.OBJECT,
            object=focused_obj
        )

        bot_msg = BotMessage(text="我看到您点击了这个订单，请问需要什么帮助？")

        turn = Turn(
            turn_id="turn_001",
            user_message=user_msg,
            bot_messages=[bot_msg]
        )

        result = HistoryBuilder.build([turn])
        print(f"结果:\n{result}")


    # 运行所有测试
    test_build_single_text_turn()
    test_build_with_object_message()
