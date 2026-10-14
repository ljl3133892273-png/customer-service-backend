# /task/action/builtin/action_listen.py
''''''
'''
`ActionListen`是一个"哨兵"，不干任何活，只起一个信号标记作用，表示"流程跑到这里，该停下来等用户输入了"。

三种模式总览:
| mode       | 用 LLM 吗 | 适用场景                         |
| ---------- | --------- | ------------------------------ |
| `static`   | 否        | 文案已写死在 YAML，直接用          |
| `rephrase` | 是        | 有模板底稿，但想说得更自然，让LLM润色 |
| `generate` | 是        | 没有预设文案，直接让LLM从零生成      |
'''

import asyncio
from typing import Any

from domain.state import DialogueState
from task.action.base import Action, ActionResult


class ActionListen(Action):
    """
    什么都不做，返回空的ActionResult
    """
    name = "action_listen"

    async def run(self, state: DialogueState, action_kwargs: dict[str, Any]) -> ActionResult:
        print("action_listen")
        return ActionResult()


if __name__ == '__main__':
    action = ActionListen()
    asyncio.run(action.run(None, None))
